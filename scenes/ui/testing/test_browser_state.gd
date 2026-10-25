class_name TestBrowserState extends RefCounted
## What the test browser window shows again when it opens (`TestBrowserWindow.open`): the search it
## had, the test it had selected and the tests it had ticked. The Testing domain's browser fills it
## from what it kept between visits; a window opened fresh leaves it alone.

## The search box's text.
var filter: String = ""
## The test path highlighted ("" none).
var selected: String = ""
## The test ids ticked.
var checked: Array = []
