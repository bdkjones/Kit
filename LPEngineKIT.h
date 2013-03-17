//
//  LPEngineKIT.h
//  CodeKit
//
//  Created by Bryan Jones on 24/11/12.
//  Copyright (c) 2012 Bryan D K Jones. All rights reserved.
//

#import <Foundation/Foundation.h>

@class LPFileKIT, LPFile, LPCompiler, LPCompilerTaskGroup;

@interface LPEngineKIT : NSObject
{
    LPCompiler  *_rootCompiler;
}

- (id) initWithRootCompiler:(LPCompiler *)root;
- (void) compile:(LPFileKIT *)aFile fromTaskGroup:(LPCompilerTaskGroup *)taskGroup;

- (NSString *) version;

@end


//
// C function prototypes
//
NSMutableArray* tokenizeString(NSString *aString);





