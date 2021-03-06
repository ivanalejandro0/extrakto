#!/bin/bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/helpers.sh"
extrakto="$CURRENT_DIR/../extrakto.py"

# options
grab_area=$(get_option "@extrakto_grab_area")
extrakto_opt=$(get_option "@extrakto_default_opt")
clip_tool=$(get_option "@extrakto_clip_tool")
fzf_tool=$(get_option "@extrakto_fzf_tool")
open_tool=$(get_option "@extrakto_open_tool")

capture_pane_start=$(get_capture_pane_start "$grab_area")
original_grab_area=${grab_area}  # keep this so we can cycle between alternatives on fzf

if [ -z "$clip_tool" ]; then
  case "`uname`" in
    'Linux')
      if [[ $(cat /proc/sys/kernel/osrelease) =~ 'Microsoft' ]]; then
        clip_tool='clip.exe'
      else
        clip_tool='xclip -i -selection clipboard >/dev/null'
      fi
      ;;
    'Darwin') clip_tool='pbcopy' ;;
    *) ;;
  esac
fi

if [[ "$open_tool" == "auto" ]]; then
  case "`uname`" in
    'Linux') open_tool='xdg-open >/dev/null' ;;
    'Darwin') open_tool='open' ;;
    *) open_tool='' ;;
  esac
fi

function capture() {

  header="tab=insert, enter=copy"
  if [ -n "$open_tool" ]; then header="$header, ctrl-o=open"; fi
  header="$header, ctrl-f=toggle filter [$extrakto_opt], ctrl-l=grab area [$grab_area]"

  case $extrakto_opt in
    'path/url') extrakto_flags='pu' ;;
    *) extrakto_flags='w' ;;
  esac

  sel=$(tmux capture-pane -pJS ${capture_pane_start} -t ! | \
    $extrakto -r$extrakto_flags | \
    $fzf_tool \
      --header="$header" \
      --expect=tab,enter,ctrl-f,ctrl-l,ctrl-o \
      --tiebreak=index)

  key=$(head -1 <<< "$sel")
  text=$(tail -n +2 <<< "$sel")

  case $key in

    enter)
      tmux set-buffer -- "$text"
      # run in background as xclip won't work otherwise
      tmux run-shell -b "tmux show-buffer|$clip_tool"
      ;;

    tab)
      tmux set-buffer -- "$text"
      tmux paste-buffer -t !
      ;;

    ctrl-f)
      if [[ $extrakto_opt == 'word' ]]; then
        extrakto_opt='path/url'
      else
        extrakto_opt='word'
      fi
      capture
      ;;

    ctrl-l)
      # cycle between options like this: recent -> full -> custom (if any)-> recent ...
      if [[ $grab_area == "recent" ]]; then
          grab_area="full"
      elif [[ $grab_area == "full" ]]; then
          grab_area="recent"

          if [[ "$original_grab_area" != "recent" && "$original_grab_area" != "full" ]]; then
              grab_area="$original_grab_area"
          fi
      else
          grab_area="recent"
      fi

      capture_pane_start=$(get_capture_pane_start "$grab_area")

      capture
      ;;

    ctrl-o)
      if [ -n "$open_tool" ]; then
        tmux run-shell -b "cd $PWD; $open_tool $text"
      else
        capture
      fi
      ;;
  esac
}

# check terminal size, zoom pane if too small
lines=$(tput lines)
if [ $lines -lt 7 ]; then
  tmux resize-pane -Z
fi

capture
