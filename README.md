The Kit Language
=======

Kit adds two things to standard HTML: include statements and variables. You can read about how to use it here:

<http://incident57.com/codekit/kit.php>


What This Is
-----------------

This repository contains the Kit compiler, as it is currently implemented in CodeKit. The code is pulled directly from CodeKit, with no changes.

This code will not build or run, as is. Rather, it's meant as a reference for folks that want to implement Kit support in other languages or tools of their own. They can look at this code to see how I did it and then adapt their approach as they see fit.

You'll find some methods, functions and classes in the code that are not included in the repo. This is because these items are part of CodeKit and are not public. These items are also not necessary to see how I built the Kit compiler. Examples include LPCompiler, LPCompilerTaskGroup, LPFileKIT, LPCompilerResultInfo, etc.




Design 
------

Although I refer to this project as a "compiler", that's not technically accurate. There is no lexer-parser-tokenizer process. (If you would like to build one of these for HTML, Godspeed. You're essentially going to attempt to write your own version of WebKit.)

Instead of getting bogged down in that nonsense, I followed a simpler approach:

	1) Take an HTML file and read it in as long string.
	2) Split that string into an array of substrings on every space, tab and newline character. The characters on which we split are included in the substrings; zero characters are discarded.
	3) Enumerate the array and see if each substring contains the character sequence that represents the start of an HTML comment: <!--
	4) If so, enter some logic that analyzes the text between this substring and all those until we reach a substring that contains the HTML commend-end delimiter: -->
	5) Along the way, copy the substrings into a complete, "final" string that becomes the text we write into the output file.

The advantage to this approach is that it lets us implement Kit without formally parsing/tokenizing HTML like your web browser does to create the DOM. That's awesome, because HTML is a language that actually *allows* syntax errors, which we would otherwise be expected to deal with. 

The disadvantage is that a formal compiler would give us more power to do things like loops, conditional statements and all that stuff. But those items were outside of the original problem scope.


	


Performance
-----------

For speed, most of the process is done in raw C with simple pointer arithmetic. We step up to Foundation and take advantage of NSString's many methods once we encounter special comments (mainly because this makes our lives much easier and there will only ever be a handful of special comments in a given Kit file, so we don't lose any appreciable speed.)

Is this implementation the fastest one you could possibly write? No. But it's ridiculously fast in practice (I test it in CodeKit on a few Kit files with thousands of lines), so it was not necessary to waste time optimizing it further only to gain a few microseconds. 

To the end user, this code runs virtually instantaneously. 




Contact
-------

If you have any questions, find me on Twitter: @bdkjones





For The Trolls
--------------

If you're about to tell me how dumb I am because I did X instead of Y or I didn't use a multiphasic, transdimensional-positronic array which is CLEARLY explained in Computer Science 101... stop right there. I understand that you are a computer genius and have forgotten more about programming than I will ever know. I do not care. Go be miserable elsewhere.





License
-------

The Kit Compiler was originally written by Bryan D K Jones in the fall of 2012. 
The code in this repository is released under an MIT license.

