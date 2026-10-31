# Reproducible source for assets/demo.gif. Regenerate with:
#   brew install vhs
#   cd awake && vhs assets/demo.tape
#
# The demo records the password-free default path against fake sudo, pmset, and
# caffeinate commands, so recording never changes this machine's sleep state.

Output assets/demo.gif

Set Shell "bash"
Set FontFamily "Menlo"
Set FontSize 16
Set Width 1120
Set Height 480
Set Padding 24
Set TypingSpeed 50ms
Set Theme {"background": "#040955", "foreground": "#f1f5f9", "cursor": "#f0ff1e", "black": "#0f172a", "red": "#d21476", "green": "#22c55e", "yellow": "#f0ff1e", "blue": "#60a5fa", "magenta": "#d21476", "cyan": "#67e8f9", "white": "#f1f5f9", "brightBlack": "#475569", "brightRed": "#f43f5e", "brightGreen": "#4ade80", "brightYellow": "#fde047", "brightBlue": "#93c5fd", "brightMagenta": "#f472b6", "brightCyan": "#a5f3fc", "brightWhite": "#ffffff", "selection": "#1e2a55", "selectionText": "#f1f5f9"}

Hide
Type "export PATH=$PWD/bin:$PWD/assets/demo-stubs:$PATH; export AWAKE_STATE_DIR=$(mktemp -d); export PS1='$ '; clear"
Enter
Sleep 500ms
Show

Sleep 800ms
Type "awake 1"
Sleep 400ms
Enter
Sleep 2800ms

Type "awake status"
Sleep 400ms
Enter
Sleep 2200ms

Type "awake off"
Sleep 400ms
Enter
Sleep 2200ms
