extends RefCounted
## The construct the scanner is meant to be unsure of: a statement that starts on the closing line of a multi-line
## string, after text that spans lines. It is left untouched and listed as uninstrumented, never read as dead.


func run() -> int:
	var s := """first line
if inside: print("string, not code")
# still the string
last"""; s += "!"
	var t := 'single "quoted" # not a comment' # a real comment
	return s.length() + t.length()
