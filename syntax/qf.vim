if exists('b:current_syntax')
    finish
endif

syn match QuickFixText /^.*/

let b:current_syntax = 'qf'
