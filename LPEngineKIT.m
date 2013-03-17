//
//  LPEngineKIT.m
//  CodeKit
//
//  Created by Bryan Jones on 24/11/12.
//  Copyright (c) 2012 Bryan D K Jones. All rights reserved.
//

#import "LPEngineKIT.h"
#import "LPConstants.h"
#import "LPLinkedFilesHelper.h"
#import "LPFile.h"
#import "LPProject.h"
#import "LPFileKIT.h"
#import "LPCompilerResultInfo.h"
#import "LPCompiler.h"
#import "LPCompilerTaskGroup.h"
#import <string.h>


//#define DEBUG_KIT_COMPILER


//
//  Data-holding class used internally
//
@interface LPKITCompilerResult : NSObject
{
    BOOL            _successful;
    NSString        *_resultMessage;
    NSString        *_compiledCode;
}
@property (nonatomic, assign) BOOL successful;
@property (nonatomic, copy) NSString *resultMessage;
@property (nonatomic, copy) NSString *compiledCode;
@end
@implementation LPKITCompilerResult
@synthesize successful = _successful, resultMessage = _resultMessage, compiledCode = _compiledCode;
- (void) dealloc
{
    [_resultMessage release];
    _resultMessage = nil;
    
    [_compiledCode release];
    _compiledCode = nil;
    
    [super dealloc];
}
@end







@implementation LPEngineKIT


- (id) initWithRootCompiler:(LPCompiler *)root
{
    self = [super init];
    if (self)
    {
        _rootCompiler = root;
    }
    return self;
}

- (void) dealloc
{
    _rootCompiler = nil;
    
    [super dealloc];
}





- (void) compile:(LPFileKIT *)aFile fromTaskGroup:(LPCompilerTaskGroup *)taskGroup
{
    __block LPCompilerResultInfo *resultInfo = [[LPCompilerResultInfo alloc] init];    // Can't do autorelease here! Do it when we pass this object on.
    resultInfo.engineType = LPEngineTypeKIT;
    resultInfo.associatedProjectDisplayValue = aFile.parentProject.displayValue;
    resultInfo.associatedProjectFullPath = aFile.parentProject.inputFullPath;
    resultInfo.typeOfProcessedFile = LPFileTypeKIT;
    resultInfo.fullPathOfProcessedFile = aFile.inputFullPath;
    resultInfo.fullPathOfTriggerFile = taskGroup.triggerFile.inputFullPath;
    resultInfo.fullPathOfOutputFile = aFile.outputFullPath;
    
    
    NSString *outPath = [[NSString alloc] initWithString:aFile.outputFullPath];     // Released after block below is done with it.
    NSString *fileName = [[NSString alloc] initWithString:aFile.inputFilename];
    
    
    dispatch_queue_t taskQ = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(taskQ,
                   ^{
                       LPKITCompilerResult *result = [self recursivelyCompileKitFileAtPath:aFile.inputFullPath withVariablesDictionary:nil andForbiddenImportFilePaths:nil];
                       
                       if (result.successful && result.compiledCode)
                       {
                           NSError *error = nil;
                           [result.compiledCode writeToFile:outPath atomically:NO encoding:NSUTF8StringEncoding error:&error];
                           
                           if (error)
                           {
                               resultInfo.primaryMessage = [NSString stringWithFormat:@"The file %@ compiled correctly, but could not be written to this path: %@", fileName, outPath];
                               resultInfo.resultType = LPCompilerResultTypeError;
                           }
                           else
                           {
                               resultInfo.primaryMessage = result.resultMessage;
                               resultInfo.resultType = LPCompilerResultTypeSuccess;
                           }
                       }
                       else if (result.successful && !result.compiledCode)
                       {
                           resultInfo.primaryMessage = [NSString stringWithFormat:@"The file %@ compiled correctly, but no output code was returned. Was the file empty?", fileName];
                           resultInfo.resultType = LPCompilerResultTypeWarning;
                       }
                       else if (!result.successful)
                       {
                           resultInfo.primaryMessage = result.resultMessage;
                           resultInfo.resultType = LPCompilerResultTypeError;
                       }
                       else
                       {
                           resultInfo.primaryMessage = result.resultMessage;
                           resultInfo.resultType = LPCompilerResultTypeSuccess;
                       }
                       
                       
                       dispatch_async(dispatch_get_main_queue(),
                                      ^{
                                          [outPath release];
                                          [fileName release];
                                          [_rootCompiler finishedCompilingFile:aFile fromTaskGroup:taskGroup withResult:[resultInfo autorelease]];
                                      });
                   });
}



- (LPKITCompilerResult *) recursivelyCompileKitFileAtPath:(NSString *)path
                                  withVariablesDictionary:(NSMutableDictionary *)variablesDict
                              andForbiddenImportFilePaths:(NSMutableArray *)previousFiles
{
    LPKITCompilerResult *result = [[LPKITCompilerResult alloc] init];
    NSString *fileName = [path lastPathComponent];
    
    if (!variablesDict) {
        variablesDict = [[NSMutableDictionary alloc] init];
    } else {
        // If the dict already exists, then we're in a recursion and need to retain it so that the release call at the very end of this method doesn't
        // drop the retain count to 0, causing a crash when we return to the level where we recursed into this run of the method.
        [variablesDict retain];
    }
    
    //
    //  This array stores the full filepaths of files we can NOT import, because doing so would create an infinite loop.
    //  We copy the array that was passed to us and pass that copy to our children recursions (if any), RATHER than maintain one global array (as we do with the variables dictionary)
    //  Because each subpath of the import tree has different import restrictions.
    //
    NSMutableArray *forbiddenImportPaths = nil;
    if (!previousFiles) {
        forbiddenImportPaths = [[NSMutableArray alloc] init];
    } else {
        // See comment on variablesDict, above
        forbiddenImportPaths = [previousFiles mutableCopy];
    }
    
    //  Make sure we haven't processed this file before. If we have, the user created an infinite import loop.
    for (NSString *oldPath in forbiddenImportPaths)
    {
        if ([oldPath caseInsensitiveCompare:path] == NSOrderedSame)
        {
            result.successful = NO;
            result.resultMessage = [NSString stringWithFormat:@"Error: infinite import loop detected. (e.g. File A imports File B, which imports File A.) You must fix this before the file can be compiled."];
            [variablesDict release];
            [forbiddenImportPaths release];
            return [result autorelease];
        }
    }
    [forbiddenImportPaths addObject:path];     // We can't import ourself.
    
    
    //
    //  Read the file and tokenize its contents
    //
    NSError *fileError = nil;
    NSString *inputCode = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&fileError];
    if (fileError || !inputCode)
    {
        result.successful = NO;
        result.resultMessage = [NSString stringWithFormat:@"This file does not exist or could not be opened for reading: %@", path];
        [variablesDict release];
        [forbiddenImportPaths release];
        return [result autorelease];
    }
    
    NSArray *comps = tokenizeString(inputCode);
    if (!comps)
    {
        result.successful = NO;
        result.resultMessage = [NSString stringWithFormat:@"Failed to tokenize %@. (Is the file UTF-8 encoded? Ensure it is not malformed.)", fileName];
        [variablesDict release];
        [forbiddenImportPaths release];
        return [result autorelease];
    }
    
    
#ifdef DEBUG_KIT_COMPILER
    NSLog(@"comps: %@", comps);
#endif

    
    NSMutableString *compiledCode = [[NSMutableString alloc] init];
    NSUInteger numberOfComponents = [comps count];
    NSUInteger currentComp;
    BOOL errorEncountered = NO;
    NSUInteger lineCount = 1;
    
    
    // Process the tokens
    for (currentComp=0; currentComp < numberOfComponents; currentComp++)
    {
        NSString *compString = [comps objectAtIndex:currentComp];
        NSRange commentStartRange = [compString rangeOfString:@"<!--"];
        NSMutableString *specialCommentString = nil;
        NSString *specialCommentPrefix = nil;                           // Needed below in debug log statement. 
        NSString *specialCommentSuffix = nil;                           // Needed at end if user does something like "<!--$var-->suffix"
        NSInteger specialCommentComp;                                   // Tracks the component that ends the special comment so we can advance to it at the end of this loop iteration, below
        BOOL isSpecialComment = NO;                                 
        
        
        //
        //  Test comp to see if it starts a special comment.
        //
        if (commentStartRange.location == NSNotFound)
        {
            // This component is not the start of a comment, so just move it over to the compiled string
            [compiledCode appendString:compString];
            
            // If this component has a newline, count it. Because of how we tokenize, the newline will ALWAYS be the final character in the component, if it exists.
            NSUInteger compLength = [compString length];
            if (compLength > 0)
            {
                unichar lastChar = [compString characterAtIndex:compLength - 1];
                if (lastChar == 0x000a || lastChar == 0x000d)       // \n, \r
                {
                    lineCount++;
                }
            }
        
            continue;
        }
        else
        {
            // This string DOES contain "<!--", so we need to see if it's a special comment
            
            // First, if the location is NOT zero, then the user did something like "texthere<!-- comment -->"
            // So we need to pull everything ahead of the comment start delimiter and throw it into the compiled output
            if (commentStartRange.location != 0)
            {
                specialCommentPrefix = [compString substringToIndex:commentStartRange.location];
                [compiledCode appendString:specialCommentPrefix];
                compString = [compString substringFromIndex:commentStartRange.location];
            }
            
            // Test comments with no spaces: <!--@import someFile.html-->, <!--$someVar value-->, <!--$someVar=value-->
            // Comp must have at least 6 characters: the comment start delimiter, the key symbol (@ or $) and an alphabetic character after that.
            if ([compString length] >= 6)   
            {
                unichar keyChar = [compString characterAtIndex:4];
                unichar peekChar = [compString characterAtIndex:5];
                isSpecialComment = ((keyChar == 0x0024 || keyChar == 0x0040) && ((peekChar > 0x004d && peekChar < 0x005b) || (peekChar > 0x0060 && peekChar < 0x007b))) ? YES : NO;
            }
            
            // Test comments WITH spaces: <!-- @import someFile.html -->, <!-- $someVar = value-->, etc.
            // Look at the first character in the NEXT comp that doesn't start with whitespace to overcome comments like this: <!--    $var=value -->
            else
            {
                NSUInteger testComp = currentComp;
                while (testComp + 1 < numberOfComponents)
                {
                    testComp++;
                    NSString *testString = [comps objectAtIndex:testComp];
                    
                    if ([testString length] > 1)
                    {
                        unichar firstChar = [testString characterAtIndex:0];
                        if (firstChar== 0x0009 || firstChar == 0x0020)      // Horizontal tab, space
                        {
                            continue;
                        }
                        else if (firstChar == 0x0024 || firstChar == 0x0040)     // $, @
                        {
                            // The next character MUST be alphabetic for this to be a valid special-comment keyword.
                            unichar peekChar = [testString characterAtIndex:1];
                            isSpecialComment = ((peekChar > 0x004d && peekChar < 0x005b) || (peekChar > 0x0060 && peekChar < 0x007b)) ? YES : NO;  // range of capitals, range of lowercase
                        }                            
                        break;
                    }
                }
            }
            
            if (!isSpecialComment)
            {
                [compiledCode appendString:compString];
                
                // If this component has a newline, count it. Because of how we tokenize, the newline will ALWAYS be the final character in the component, if it exists.
                NSUInteger compLength = [compString length];
                if (compLength > 0)
                {
                    unichar lastChar = [compString characterAtIndex:compLength - 1];
                    if (lastChar == 0x000a || lastChar == 0x000d)       // \n, \r
                    {
                        lineCount++;
                    }
                }
                
                continue;
            }
            else
            {
                // We've got a special comment. String together all the comps from the current one to the next comp that contains the "-->" substring.
                specialCommentString = [[[NSMutableString alloc] init] autorelease];
                
                for (specialCommentComp = currentComp; specialCommentComp < numberOfComponents; specialCommentComp++)
                {
                    NSString *commentCompString = [comps objectAtIndex:specialCommentComp];
                    [specialCommentString appendString:commentCompString];
                    
                    // If this component contains "-->", then we end the special comment
                    NSRange commentEndRange = [commentCompString rangeOfString:@"-->" options:NSBackwardsSearch];
                    if (commentEndRange.location != NSNotFound)
                    {
                        // Is there any text after the "-->" in this comp? (Other than a newline.)
                        // If so, we'll need to add that text to the compiled output once we handle this special comment, so save that text for later
                        NSUInteger length = [commentCompString length];
                        if (commentEndRange.location != length - 3)
                        {
                            if (commentEndRange.location + 3 < length)
                            {
                                NSString *possibleSuffix = [commentCompString substringFromIndex:commentEndRange.location + 3];
                                
                                if (![possibleSuffix isEqualToString:@"\n"] && ![possibleSuffix isEqualToString:@"\r\n"] && ![possibleSuffix isEqualToString:@"\r"])
                                {
                                    specialCommentSuffix = possibleSuffix;
                                }
                            }
                        }
                        break;
                    }
                }
            }
        }
        
        
        if (!specialCommentString)
        {
            errorEncountered = YES;
            result.successful = NO;
            result.resultMessage = [NSString stringWithFormat:@"Line %lu of %@: Found a Kit comment, but could not parse it into a full string. (Ensure that the file is UTF-8 encoded and not damaged.)", lineCount, fileName];
            break;  // out of the overall loop that goes through tokens.
        }
        
        
        //
        //  Parse the special comment for keyword and predicate
        //
        NSString *keyword = nil;
        NSString *predicate = nil;

        NSInteger fullCommentLength = [specialCommentString length];
        unichar fullCommentBuffer[fullCommentLength + 1];
        [specialCommentString getCharacters:fullCommentBuffer range:NSMakeRange(0, fullCommentLength)];
        
        // Used below to record how far we've parsed the comment
        long currentFullCommentIndex = -1;
        
        // First, get the keyword. (Either @import or a variable name)
        unichar keywordBuffer[fullCommentLength + 1];
        long keywordIndex = 0;
        BOOL keywordStarted = NO;
        
        long k;
        for (k=0; k<fullCommentLength; k++)
        {
            currentFullCommentIndex++;
            unichar current = fullCommentBuffer[k];
            
            if (current == 0x0024 || current == 0x0040)     // $, @
            {
                // Skip everything until we get to the first $ or @ character, which is the start of the keyword.
                keywordStarted = YES;
                keywordBuffer[keywordIndex] = current;
                keywordIndex++;
                continue;
            }
            else if (keywordStarted)
            {
                if (current == 0x0020 || current == 0x003d || current == 0x0009 || current == 0x003a)
                {
                    // If we hit a space, tab, equals sign or colon, stop
                    break;
                }
                else if (current == 0x002d)
                {
                    // If this is a hyphen, decide if it's part of the keyword or the beginning of the --> delimiter
                    if (k + 2 < fullCommentLength)
                    {
                        unichar peek1 = fullCommentBuffer[k+1];
                        unichar peek2 = fullCommentBuffer[k+2];
                        
                        if (peek1 == 0x002d && peek2 == 0x003e)
                        {
                            // if the next two characters are "->", the hyphen is part of the comment-end delimiter.
                            break;
                        }
                        else
                        {
                            keywordBuffer[keywordIndex] = current;
                            keywordIndex++;
                            continue;
                        }
                    }
                    else
                    {
                        // We don't have at least two slots left in the full comment. The comment is probably malformed, but we'll just roll with it.
                        keywordBuffer[keywordIndex] = current;
                        keywordIndex++;
                        continue;
                    }
                }
                else
                {
                    keywordBuffer[keywordIndex] = current;
                    keywordIndex++;
                    continue;
                }
            }
        }
        
        keyword = [NSString stringWithCharacters:keywordBuffer length:keywordIndex];
        

        //  Now get the predicate (everything after the keyword) It may be nothing (e.g. <!--$useThisVar-->)
        unichar predicateBuffer[fullCommentLength + 1];
        long predicateIndex = 0;
        BOOL predicateStarted = NO;
        
        long j;
        for (j=currentFullCommentIndex; j<fullCommentLength; j++)
        {
            unichar current = fullCommentBuffer[j];
            
            if ((current == 0x0020 || current == 0x003d || current == 0x0009 || current == 0x003a || current == 0x000a || current == 0x000d) && !predicateStarted)
            {
                // Skip all space, equals signs, tabs, colons, '\n' and '\r' until we find the first character that's NOT one of these.
                // Note: don't do "isAlphanumeric" check because some predicates will be: "../someFile.kit" (with quotes)
                continue;
            }
            else if (current == 0x002d)     // hyphen
            {
                predicateStarted = YES;
                
                // If this is a hyphen, we need to see if it's part of the predicate, or part of the end-comment delimiter (-->)
                // Do we have at least 2 slots left in the string?
                if (j + 2 < fullCommentLength)
                {
                    unichar peek1 = fullCommentBuffer[j+1];
                    unichar peek2 = fullCommentBuffer[j+2];
                    
                    if (peek1 == 0x002d && peek2 == 0x003e)
                    {
                        // if the next two characters are "->", we've reached the end of the predicate.
                        // if the LAST character we added to the predicate buffer was a space, delete it
                        if (predicateIndex - 1 >= 0)
                        {
                            unichar past = predicateBuffer[predicateIndex - 1];
                            if (past == 0x0020)
                            {
                                predicateBuffer[predicateIndex - 1] = 0x0000;
                                predicateIndex--;   // Decrement so that when we form the NSString from this buffer, the length is cut by one.
                            }
                        }
                        break;
                    }
                    else
                    {
                        predicateBuffer[predicateIndex] = current;
                        predicateIndex++;
                        continue;
                    }
                }
                else
                {
                    // We don't have at least two slots left in the full comment. The comment is probably malformed, but we'll just roll with it.
                    predicateBuffer[predicateIndex] = current;
                    predicateIndex++;
                    continue;
                }
            }
            else
            {
                predicateStarted = YES;
                
                // This character is a generic one, or a space, tab, colon or equals sign found after the start of the predicate.
                predicateBuffer[predicateIndex] = current;
                predicateIndex++;
                continue;
            }
        }
        
        // The predicate may not exist (e.g. <!--$useThisVar-->), so be careful:
        predicate = (predicateIndex > 0) ? [NSString stringWithCharacters:predicateBuffer length:predicateIndex] : nil;
        
        
        
#ifdef DEBUG_KIT_COMPILER
        NSLog(@"Special Comment Found: %@", specialCommentString);
        NSLog(@"     Line:       %lu", lineCount);
        NSLog(@"     Keyword:    %@", keyword);
        NSLog(@"     Predicate:  %@\n\n", predicate);
        NSLog(@"     scPrefix:   %@", specialCommentPrefix);
        NSLog(@"     scSuffix:   %@\n\n", specialCommentSuffix);
#endif
        
        
        //
        //  Now that we've got a keyword and predicate (maybe), do something with them
        //
        if (keyword)
        {
            if ([keyword caseInsensitiveCompare:@"@import"] == NSOrderedSame || [keyword caseInsensitiveCompare:@"@include"] == NSOrderedSame)
            {
                // We have an import statement
                if (!predicate)
                {
                    errorEncountered = YES;
                    result.successful = NO;
                    result.resultMessage = [NSString stringWithFormat:@"Line %lu of %@: Missing a filepath after the import/include keyword in this Kit comment: %@", lineCount, fileName, specialCommentString];
                    break;
                }
                else
                {
                    // We allow comma-separated import lists: <!-- @import someFile.kit, otherFile.html -->
                    NSArray *imports = [predicate componentsSeparatedByString:@","];
                    NSFileManager *fm = [NSFileManager defaultManager];
                    NSArray *frameworkFolders = [_rootCompiler allPossibleFoldersForImportedFrameworkFiles];
                    
                    for (NSString *importString in imports)
                    {
                        BOOL fileFound = NO;
                        NSString *cleanedImportString = pruneCommonImportSyntaxCharacters(importString);
                        NSString *fullImportFilePath = resolveRelativePaths(cleanedImportString, path, NO);
                        
                        // The file extension is optional. Add it if missing.
                        if ([[fullImportFilePath pathExtension] caseInsensitiveCompare:@""] == NSOrderedSame)
                        {
                            fullImportFilePath = [fullImportFilePath stringByAppendingPathExtension:@"kit"];
                        }
                        
                        // Allow for an optional leading underscore. We'll test the actual filename specified in the @import statement first,
                        // but if that isn't valid, then we add or remove the leading underscore and test THAT filename.
                        NSString *filename1 = [fullImportFilePath lastPathComponent];
                        NSString *filename2 = nil;
                        NSString *rootPath = [fullImportFilePath stringByDeletingLastPathComponent];
                        if (![filename1 hasPrefix:@"_"]) {
                            filename2 = [NSString stringWithFormat:@"_%@", filename1];
                        } else {
                            filename2 = [filename1 stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"_"]];
                        }
                        
                        
                        if ([fm fileExistsAtPath:fullImportFilePath])
                        {
                            fileFound = YES;
                        }
                        else if ([fm fileExistsAtPath:[rootPath stringByAppendingPathComponent:filename2]])
                        {
                            fullImportFilePath = [rootPath stringByAppendingPathComponent:filename2];
                            fileFound = YES;
                        }
                        else
                        {
                            // Neither "file.kit" nor "_file.kit" were in the specified locations. Check Frameworks, starting with the
                            // exact name specified in the @import statement, then swapping in/out the underscore
                            for (NSString *frameFolder in frameworkFolders)
                            {
                                NSString *testPath = [frameFolder stringByAppendingPathComponent:filename1];
                                if ([fm fileExistsAtPath:testPath])
                                {
                                    fullImportFilePath = testPath;
                                    fileFound = YES;
                                    break;
                                }
                            }
                            
                            if (!fileFound)
                            {
                                // Last resort: check all folders for the version of the name with/without underscore
                                for (NSString *frameFolder in frameworkFolders)
                                {
                                    NSString *testPath = [frameFolder stringByAppendingPathComponent:filename2];
                                    if ([fm fileExistsAtPath:testPath])
                                    {
                                        fullImportFilePath = testPath;
                                        fileFound = YES;
                                        break;
                                    }
                                }
                            }
                        }
                        
                        
                        if (!fileFound)
                        {
                            errorEncountered = YES;
                            result.successful = NO;
                            result.resultMessage = [NSString stringWithFormat:@"Line %lu in %@: You're attempting to import a file that does not exist in the specified location nor in any CodeKit Framework: %@", lineCount, fileName, cleanedImportString];
                            break;
                        }
                        

                        NSString *extension = [fullImportFilePath pathExtension];
                        if ([extension caseInsensitiveCompare:@"kit"] == NSOrderedSame)
                        {
                            // Recurse and compile
                            LPKITCompilerResult *importResult = [self recursivelyCompileKitFileAtPath:fullImportFilePath withVariablesDictionary:variablesDict andForbiddenImportFilePaths:forbiddenImportPaths];
                            
                            if (importResult.successful && importResult.compiledCode)
                            {
                                [compiledCode appendString:importResult.compiledCode];
                            }
                            else
                            {
                                errorEncountered = YES;
                                result.successful = NO;
                                result.resultMessage = importResult.resultMessage;
                                break;
                            }
                        }
                        else
                        {
                            // This is a non-Kit file, so just throw its text into place
                            NSError *error = nil;
                            NSString *text = [NSString stringWithContentsOfFile:fullImportFilePath encoding:NSUTF8StringEncoding error:&fileError];
                            
                            if (error || !text)
                            {
                                errorEncountered = YES;
                                result.successful = NO;
                                result.resultMessage = [NSString stringWithFormat:@"Line %lu in %@: The imported file at this path does not exist or is unreadable: %@", lineCount, fileName, fullImportFilePath];
                                break;
                            }
                            else if (text)
                            {
                                [compiledCode appendString:text];
                            }
                        }
                    }
                    
                    if (errorEncountered) break; // out of the overall "comps" loop.
                }
            }
            else
            {
                // We have a variable
                if (predicate)
                {
                    // If we've got a predicate, we're assigning a value to this variable
                    [variablesDict setObject:predicate forKey:keyword];
                }
                else
                {
                    NSString *insert = [variablesDict objectForKey:keyword];
                    
                    if (insert)
                    {
                        [compiledCode appendString:insert];
                    }
                    else
                    {
                        errorEncountered = YES;
                        result.successful = NO;
                        result.resultMessage = [NSString stringWithFormat:@"Line %lu of %@: The variable %@ is undefined.", lineCount, fileName, keyword];
                        break;
                    }
                }
            }
        }
        else
        {
            // Keyword was nil, which is a massive error at this point.
            errorEncountered = YES;
            result.successful = NO;
            result.resultMessage = [NSString stringWithFormat:@"Line %lu of %@: Unable to find an appropriate keyword (either \"@import\" or a variable name) in this Kit comment: %@", lineCount, fileName, specialCommentString];
            break;
        }
        
        
        //
        //  It's possible (likely) that the special comment contained one or more newlines, which we need to account for.
        //  Otherwise, next time we use it the lineCount will be missing the newlines in this special comment and will not indicate the correct line.
        //
        long t;
        for (t=0; t<fullCommentLength; t++)
        {
            unichar current = fullCommentBuffer[t];
            
            if (current == 0x000a)    // \n
            {
                lineCount++;
            }
            else if (current == 0x000d)     // \r
            {
                // if this is a '\r', count it as a newline ONLY if the very next character is not a '\n'
                if (t+1 < fullCommentLength)
                {
                    unichar peekChar = fullCommentBuffer[t+1];
                    if (peekChar != 0x000a) lineCount++;
                }
            }
        }
        
        
        //  If we had any text after the special comment's closing tag (e.g. "-->textHere"), add that:
        if (specialCommentSuffix) [compiledCode appendString:specialCommentSuffix];
        
        //  Advance the 'currentComp' number to skip all components involved in the special comment we just handled.
        //  This removes the special comment from the compiled output.
        currentComp = specialCommentComp;
    }
    
    
    //
    //  After handling all of the tokenized comps:
    //
    if (!errorEncountered)
    {
        result.compiledCode = compiledCode;
        result.successful = YES;
        result.resultMessage = @"Compiled successfully.";
    }

    [variablesDict release];
    [compiledCode release];
    [forbiddenImportPaths release];
    
    return [result autorelease];
}








- (NSString *) version
{
    return @"1.1";
}



@end








#pragma mark -
#pragma mark C FUNCTIONS
#pragma -----------------------------------------------------------------------------------------------------------------


NSMutableArray* tokenizeString(NSString *aString)
{
    NSMutableArray *comps = [[NSMutableArray alloc] init];
    const char *inputString = [aString cStringUsingEncoding:NSUTF8StringEncoding];
    
    size_t stringLength = strlen(inputString);
    
    // buffer is where we'll put characters until we hit a character that we split on.
    int currentBufferSize = 100;
    char *buffer = (char *)malloc(currentBufferSize);
    int nextAvailableBufferSlot = 0;
    
    if (buffer == NULL) {
        NSLog(@"Failed to allocate memory for the buffer in LPEngineKit -tokenizeString:");
        [comps release];
        return nil;
    }
    
    int i;
    for (i=0; i<stringLength; i++)
    {
        unichar currentChar = inputString[i];
        
        BOOL shouldSplit = NO;

        if (currentChar == 0x0020 || currentChar == 0x0009 || currentChar == 0x000a)
        {
            // We always split on SPACE (0x0020), TAB (0x0009) and LF (\n) (0x000a)
            shouldSplit = YES;
        }
        else if (currentChar == 0x000d)
        {
            // We split on CR(\r) (0x000d) ONLY if it's not immediately followed by an '\n'.
            // OS X uses '\n' while Windows uses '\r\n'. OS 9 and some less popular OSes use '\r' alone as the newline character
            if (i+1 < stringLength)
            {
                unichar peekChar = inputString[i+1];
                shouldSplit = (peekChar == 0x000a) ? NO : YES;
            }
        }
        else if (currentChar == 0x003e)
        {
            // We also split on ">" IF that character is immediately followed by "<"
            // This solves the issue where the user does something like: <!--$var value--><!--$var value-->
            int peekIndex = i+1;
            if (peekIndex < stringLength)
            {
                char peekChar = inputString[peekIndex];
                if (peekChar == 0x003c) shouldSplit = YES;
            }
        }
        
        
        if (nextAvailableBufferSlot <= currentBufferSize - 2)       // One to adjust for zero-indexing, one to leave room to add a terminating null character.
        {
            buffer[nextAvailableBufferSlot] = currentChar;
            nextAvailableBufferSlot++;
        }
        else
        {
            // We need a bigger buffer.
            int oldBufferSize = currentBufferSize;
            currentBufferSize += 100;
            char *newBuffer = (char *)malloc(currentBufferSize);
            
            if (newBuffer == NULL) {
                NSLog(@"Failed to reallocate additional memory for the buffer in LPEngineKit -tokenizeString:");
                free(buffer);
                [comps release];
                return nil;
            }
            
            memcpy(newBuffer, buffer, oldBufferSize);
            free (buffer);
            buffer = newBuffer;
            
            // No need to check; we've definitely got room for this character in the re-alloced buffer.
            buffer[nextAvailableBufferSlot] = currentChar;
            nextAvailableBufferSlot++;
        }
        
        if (shouldSplit || i+1 == stringLength)
        {
            // Pad the remaining buffer slots with null
            int k;
            for (k = nextAvailableBufferSlot; k <= currentBufferSize; k++) {
                buffer[nextAvailableBufferSlot] = '\0';
            }
            
            NSString *component = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
            [comps addObject:component];
            
            // Clear the buffer & reset the variable that keeps track of how many characters we've added to it
            memset(buffer, 0, (sizeof(char) * currentBufferSize));
            nextAvailableBufferSlot = 0;
        }
    }
    
    free(buffer);
    return [comps autorelease];
}