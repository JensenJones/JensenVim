; extends

; Use Tree-sitter's alignment engine for C++ list and expression styles.
; Namespace contents use the same block indentation as the rest of jvim C++.
(namespace_definition
  body: (declaration_list) @indent.begin)

((initializer_list) @indent.align
  (#set! indent.open_delimiter "{")
  (#set! indent.close_delimiter "}"))

((conditional_expression) @indent.align
  (#set! indent.open_delimiter "?")
  (#set! indent.close_delimiter ":")
  (#set! indent.increment 0))

((template_argument_list) @indent.align
  (#set! indent.open_delimiter "<")
  (#set! indent.close_delimiter ">"))

((template_parameter_list) @indent.align
  (#set! indent.open_delimiter "<")
  (#set! indent.close_delimiter ">"))

; Preserve leading-comma style when a list already uses it.
((argument_list) @indent.align
  (#lua-match? @indent.align "\n%s*,")
  (#set! indent.open_delimiter ",")
  (#set! indent.increment 0))
