#!/bin/bash
#
# Usage:
#   ./parse-errors.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

source test/common.sh

# Run with SH=bash too
SH=${SH:-bin/osh}

banner() {
  echo
  echo ===== CASE: "$@" =====
  echo
}

_error-case() {
  banner "$@"
  echo
  $SH -c "$@"

  # NOTE: This works with osh, not others.
  local status=$?
  if test $status != 2; then
    die "Expected status 2, got $?"
  fi
}

# All in osh/word_parse.py
patsub() {
  set +o errexit

  _error-case 'echo ${x/}'  # pattern must not be empty

  # These are a little odd
  _error-case 'echo ${x//}'
  #_error-case 'echo ${x///}'

  #_error-case 'echo ${x/foo}'
  #_error-case 'echo ${x//foo}'

  # This should be a different error?  It should be an empty pattern?
  _error-case 'echo ${x///foo}'

  # Newline in replacement pattern
  #_error-case 'echo ${x//foo/replace
#}'
  #_error-case 'echo ${x//foo/replace$foo}'
}

# osh/word_parse.py
word-parse() {
  set +o errexit

  _error-case 'echo ${'

  # This parses like a slice, but that's OK.  Maybe talk about arithmetic
  # expression.  Maybe say where it started?
  _error-case '${foo:}'

  _error-case 'echo ${a[@Z'

  _error-case 'echo ${x.}'
  _error-case 'echo ${!x.}'

  # Slicing
  _error-case 'echo ${a:1;}'
  _error-case 'echo ${a:1:2;}'

  # I don't seem to be able to tickle errors here
  #_error-case 'echo ${a:-}'
  #_error-case 'echo ${a#}'

  _error-case 'echo ${#a.'

  # for (( ))
  _error-case 'for (( i = 0; i < 10; i++ ;'
  # Hm not sure about this
  _error-case 'for (( i = 0; i < 10; i++ /'

  _error-case 'echo @(extglob|foo'
}

array-literal() {
  set +o errexit

  # Array literal with invalid TokenWord.
  _error-case 'a=(1 & 2)'
  _error-case 'a= (1 2)'
  _error-case 'a=(1 2'
  _error-case 'a=(1 ${2@} )'  # error in word inside array literal
}

arith-context() {
  set +o errexit

  # $(( ))
  _error-case 'echo $(( 1 + 2 ;'
  _error-case 'echo $(( 1 + 2 );'
  _error-case 'echo $(( '
  _error-case 'echo $(( 1'

  # Non-standard arith sub $[1 + 2]
  _error-case 'echo $[ 1 + 2 ;'

  # What's going on here?   No location info?
  _error-case 'echo $[ 1 + 2 /'

  _error-case 'echo $[ 1 + 2 / 3'
  _error-case 'echo $['

  # (( ))
  _error-case '(( 1 + 2 /'
  _error-case '(( 1 + 2 )/'
  _error-case '(( 1'
  _error-case '(('

  # Should be an error
  _error-case 'a[x+]=1'

  # This is not an error, it just fails to detect?  Might want to be stricter
  # about it.
  _error-case 'a[]=1'
}

arith-expr() {
  set +o errexit

  # BUG: the token is off here
  _error-case '$(( 1 + + ))'

  # BUG: not a great error either
  _error-case '$(( 1 2 ))'

  # Triggered a crash!
  _error-case '$(( - ; ))'

  # NOTE: This is confusing, should point to ` for command context?
  _error-case '$(( ` ))'

  _error-case '$(( $ ))'

  # "Can't assign to None" is misleading.
  # From wild/src/distro/portage/bin/helper-functions.sh
  _error-case '$(( ${var} = fd ))'
}

bool-expr() {
  set +o errexit

  # Extra word
  _error-case '[[ a b ]]'
  _error-case '[[ a "a"$(echo hi)"b" ]]'

  # Wrong error message
  _error-case '[[ a == ]]'

  # Invalid regex
  _error-case '[[ $var =~ * ]]'
  _error-case '[[ $var =~ \\ ]]'

  # Unbalanced parens
  _error-case '[[ ( 1 == 2 - ]]'

  _error-case '[[ == ]]'
  _error-case '[[ ) ]]'
  _error-case '[[ ( ]]'

  _error-case '[[ ;;; ]]'
  _error-case '[['
}

# These don't have any location information.
test-builtin() {
  set +o errexit

  # Extra token
  _error-case '[ x -a y f ]'
  _error-case 'test x -a y f'

  # Missing closing ]
  _error-case '[ x '

  # Hm some of these errors are wonky.  Need positions.
  _error-case '[ x x ]'

  _error-case '[ x x x ]'

  # -o tests if an option is enabled.
  #_error-case '[ -o x ]'
}

quoted-strings() {
  set +o errexit

  _error-case '"unterminated double'

  _error-case "'unterminated single"

  _error-case '
  "unterminated double multiline
  line 1
  line 2'

  _error-case "
  'unterminated single multiline
  line 1
  line 2"
}

cmd-parse() {
  set +o errexit

  _error-case 'FOO=1 break'
  _error-case 'break 1 2'
  _error-case 'break >out'

  _error-case 'for x in &'

  _error-case 'for (( i=0; i<10; i++ )) ls'

  _error-case 'for $x in 1 2 3; do echo $i; done'
  _error-case 'for x.y in 1 2 3; do echo $i; done'
  _error-case 'for x in 1 2 3; &'
  _error-case 'for foo BAD'

  _error-case 'x"y"() { echo hi; }'

  _error-case 'function x"y" { echo hi; }'

  _error-case '}'

  _error-case 'case foo in *) echo '

  _error-case 'ls foo|'
  _error-case 'ls foo&&'

  _error-case 'foo()'
}

redirect() {
  set +o errexit

  _error-case 'echo < <<'
  _error-case 'echo $( echo > >>  )'

  _error-case 'FOO=1 BAR=2 > out'
  _error-case '> out FOO=1 BAR=2'

  _error-case 'local BAR=2 > out'
}

simple-command() {
  set +o errexit

  _error-case 'PYTHONPATH=. FOO=(1 2) python'
  _error-case 'echo foo FOO=(1 2)'

  _error-case 'PYTHONPATH+=1 python'
}

assign() {
  set +o errexit
  _error-case 'local name$x'
  _error-case 'local "ab"'
  _error-case 'local a.b'

  _error-case 'FOO=1 local foo=1'

}

# I can't think of any other here doc error conditions except arith/var/command
# substitution, and unterminated.
here-doc() {
  set +o errexit

  # Arith in here doc
  _error-case 'cat <<EOF
$(( 1 * ))  
EOF
'

  # Varsub in here doc
  _error-case 'cat <<EOF
invalid: ${a!}
EOF
'

  _error-case 'cat <<EOF
$(for x in )
EOF
'
}

here-doc-delimiter() {
  set +o errexit

  # NOTE: This is more like the case where.
  _error-case 'cat << $(invalid here end)'

  # TODO: Arith parser doesn't have location information
  _error-case 'cat << $((1+2))'
  _error-case 'cat << a=(1 2 3)'
  _error-case 'cat << \a$(invalid)'

  # Actually the $invalid part should be highlighted... yeah an individual
  # part is the problem.
  #"cat << 'single'$(invalid)"
  _error-case 'cat << "double"$(invalid)'
  _error-case 'cat << ~foo/$(invalid)'
  _error-case 'cat << $var/$(invalid)'
}

cases-in-strings() {
  set +o errexit

  cmd-parse
  simple-command
  redirect
  here-doc
  here-doc-delimiter

  # Word
  word-parse
  array-literal
  patsub
  quoted-strings

  # Arith
  arith-context
  arith-expr

  bool-expr
  test-builtin
}

# Cases in their own file
cases-in-files() {
  set +o errexit  # Don't fail

  for t in test/parse-errors/*.sh; do
    banner $t
    $SH $t
  done
}

all() {
  cases-in-strings

  echo
  echo ----------------------
  echo

  cases-in-files

  # Always passes
  return 0
}

run-for-release() {
  run-other-suite-for-release parse-errors all
}

"$@"
