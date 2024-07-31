if exists('b:current_syntax')
    finish
endif

lua require('quicker.syntax').set_syntax()

let b:current_syntax = 'qf'
