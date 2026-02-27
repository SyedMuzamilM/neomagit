if exists("b:current_syntax")
  finish
endif

syn match NeomagitSyntaxTitle /^Neomagit$/
syn match NeomagitSyntaxMeta /^\%(Repo\|Branch\|Operation\):.*$/
syn match NeomagitSyntaxSection /^\[[+-]\] .*$/
syn match NeomagitSyntaxHunk /^    @@ .*@@.*$/
syn match NeomagitSyntaxHint /^Press ? for keymap help\.$/
syn match NeomagitSyntaxHelp /^\%(q close\|s stage\|c commit\|f fetch\|r rebase\|l open full log\).*$/
syn match NeomagitSyntaxStash /^  \d\+\. stash@{[0-9]\+}:.*$/
syn match NeomagitSyntaxCommit /^  \d\+\. [0-9a-f]\{7,40} .*$/

hi def link NeomagitSyntaxTitle NeomagitTitle
hi def link NeomagitSyntaxMeta NeomagitMeta
hi def link NeomagitSyntaxSection NeomagitSection
hi def link NeomagitSyntaxHunk NeomagitHunk
hi def link NeomagitSyntaxHint NeomagitHint
hi def link NeomagitSyntaxHelp NeomagitHelp
hi def link NeomagitSyntaxStash NeomagitStash
hi def link NeomagitSyntaxCommit NeomagitCommit

let b:current_syntax = "neomagit"
