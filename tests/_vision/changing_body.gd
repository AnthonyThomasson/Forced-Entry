extends StaticBody2D
## Test helper (not a test): a solid that can say `changed`, as a door does; the test emits it.

@warning_ignore("unused_signal")  # emitted by the test that holds the body
signal changed
