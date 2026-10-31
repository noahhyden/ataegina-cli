## A heredoc body is not a comment

ataegina emits usage text, a config header and shell completions from quoted heredocs whose bodies legitimately start lines with `#`, so the bash scanner tracks heredoc delimiters and skips those bodies; missing this flags output as prose.
