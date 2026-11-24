# The shell evaluates its own builtins here so cd, functions, aliases, and
# variables have the usual lifetime. Python has its own persistent namespace.
case $nw_language in
    nsh)
        nw_config=$NSH_HOME
        if [ -r "$nw_config/etc/nsh.bash" ]; then . "$nw_config/etc/nsh.bash"; fi
        ;;
    shn) nw_config=$SHN_HOME ;;
    nhs) nw_config=${NHS_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/nhs} ;;
esac
if [ -d "$nw_config/bin" ]; then PATH=$nw_config/bin:$PATH; export PATH; fi

nw_history=$nw_config/history
if [ -n "${BASH_VERSION:-}" ]; then
    shopt -s expand_aliases
    if [ -r "$nw_history" ]; then builtin history -r "$nw_history"; fi
fi
nw_native_status=0
nw_source_line=0
nw_pending=
nw_compiled=
nw_last=
trap 'nw_interrupted=yes' INT

nw_remember() {
    case $1 in
        ''|' '*) return ;;
    esac
    if [ -n "${BASH_VERSION:-}" ]; then builtin history -s "$1"; fi
    (umask 077; mkdir -p "$nw_config"; printf '%s\n' "$1" >> "$nw_history")
}

nw_reply() {
    if ! nw_agent "$nw_primer" "$1" < "$nw_work/context" > "$nw_work/reply"; then
        return 1
    fi
    IFS= read -r nw_marker < "$nw_work/reply"
    case $nw_marker in
        @ask)
            nw_pending=yes
            sed '1d' "$nw_work/reply" >&2
            printf 'Agent question:\n' >> "$nw_work/context"
            sed '1d' "$nw_work/reply" >> "$nw_work/context"
            return 0 ;;
        @code)
            [ "$nw_mode" = c ] || { cat "$nw_work/reply"; return; }
            sed '1d' "$nw_work/reply" > "$nw_work/correction"
            if [ -s "$nw_work/correction" ] && nw_native_check "$nw_work/correction"; then
                nw_compiled=yes
                cat "$nw_work/correction"
                printf '%s\n' 'Use :run to execute this correction or :link NAME to save it.' >&2
                return 0
            fi
            printf '%s\n' 'The correction failed native validation.' >&2
            return 2 ;;
        @fail)
            sed '1d' "$nw_work/reply" >&2
            return 1 ;;
        *)
            if [ "$nw_mode" = c ] || [ "$nw_mode" = a ]; then
                printf '%s\n' 'The backend did not follow the turn protocol.' >&2
                return 2
            fi
            cat "$nw_work/reply" ;;
    esac
}

nw_restore_status() { return "$1"; }
nw_run_native() {
    nw_native_status_before=$nw_native_status
    nw_native_status=0
    nw_source_invalid=no
    printf '%s\n' "$1" > "$nw_work/source"
    if nw_native_check "$nw_work/source" "$((nw_source_line - 1))" "<repl>" 2> "$nw_work/error"; then
        case $nw_language in
            nsh)
                nw_restore_status "$nw_native_status_before"
                eval "$1" 2> "$nw_work/error"
                nw_native_status=$? ;;
            *)
                case $nw_language in
                    shn) speech_program '<repl>' no "$((nw_source_line - 1))" 3< "$nw_work/source" 2> "$nw_work/error" ;;
                    *) nw_native_run "$nw_work/source" 2> "$nw_work/error" ;;
                esac
                nw_native_status=$? ;;
        esac
    else
        nw_source_invalid=yes
        nw_native_status=65
    fi
    cat "$nw_work/error" >&2
}

while :; do
    nw_shown_permission=$nw_permission
    case $nw_mode in c|a) nw_shown_permission=text ;; esac
    nw_prompt="$nw_name[$nw_mode:$nw_strictness:$nw_effort:$nw_shown_permission]"
    if [ "$nw_language" = shn ]; then nw_prompt="$nw_prompt $((nw_source_line + 1))"; fi
    if [ -n "$nw_pending" ]; then nw_prompt="$nw_prompt?"; fi
    nw_interrupted=
    PS1="$nw_prompt> "
    # Readline can consume Ctrl+C before a noninteractive shell gets its
    # trap. Give the reader its own process and keep the REPL state here.
    (
        trap 'exit 130' INT
        nw_line=
        nw_read_status=0
        if [ -n "${BASH_VERSION:-}" ]; then
            IFS= read -e -r -p "$PS1" nw_line || nw_read_status=$?
        else
            printf '%s' "$PS1" >&2
            IFS= read -r nw_line || nw_read_status=$?
        fi
        printf '%s' "$nw_line" > "$nw_work/line"
        exit "$nw_read_status"
    )
    nw_read_status=$?
    if [ "$nw_read_status" -eq 130 ] || [ -n "$nw_interrupted" ]; then
        nw_pending= nw_compiled= nw_native_status=130
        printf '\n' >&2
        continue
    fi
    nw_line=$(cat "$nw_work/line")
    if [ "$nw_read_status" -ne 0 ] && [ -z "$nw_line" ]; then
        printf '\n' >&2
        exit "$nw_native_status"
    fi

    case $nw_line in
        :quit|:exit) exit "$nw_native_status" ;;
        :cancel) nw_pending= nw_compiled=; nw_native_status=0; continue ;;
        :mode\ *)
            nw_choice=${nw_line#* }
            case $nw_choice in c|a|r|l) nw_mode=$nw_choice; nw_pending=; continue ;; esac ;;
        :nitpick\ *)
            nw_choice=${nw_line#* }
            case $nw_choice in 0|1|2) nw_strictness=$nw_choice; nw_pending=; continue ;; esac ;;
        :effort\ *)
            nw_choice=${nw_line#* }
            case $nw_choice in none|low|medium|high|xhigh|max) nw_effort=$nw_choice; continue ;; esac ;;
        :permission\ *)
            nw_choice=${nw_line#* }
            case $nw_choice in text|read|write) nw_permission=$nw_choice; continue ;; esac ;;
        :link\ *)
            if [ -n "$nw_compiled" ]; then nw_target=$nw_work/correction
            elif [ -n "$nw_last" ]; then nw_target=$nw_work/last
            else printf '%s\n' 'There is no source to link.' >&2; continue; fi
            nw_link "${nw_line#* }" "$nw_target"
            nw_native_status=$?
            continue ;;
        :run)
            if [ -n "$nw_compiled" ]; then
                nw_source_line=$((nw_source_line + 1))
                nw_run_native "$(cat "$nw_work/correction")"
                if [ "$nw_native_status" -eq 0 ]; then cp "$nw_work/correction" "$nw_work/last"; nw_last=yes; fi
                nw_compiled=
            else
                printf '%s\n' 'There is no correction to run.' >&2
            fi
            continue ;;
        :paste)
            nw_line=
            while IFS= read -r nw_part && [ -n "$nw_part" ]; do nw_line=${nw_line:+$nw_line
}$nw_part; done
            ;;
        ld.so\ *)
            if [ "$nw_language" = nsh ]; then
                nw_source_line=$((nw_source_line + 1))
                nw_restore_status "$nw_native_status"
                eval "${nw_line#* }"
                nw_native_status=$?
                continue
            fi ;;
        :*) printf '%s\n' 'Unknown REPL command. Use --help for commands.' >&2; continue ;;
    esac

    [ -n "$nw_line" ] || continue
    nw_remember "$nw_line"
    if [ -n "$nw_pending" ]; then
        nw_pending=
        printf 'User answer:\n%s\n' "$nw_line" >> "$nw_work/context"
        nw_reply "$nw_original"
        nw_native_status=$?
        continue
    fi

    nw_source_line=$((nw_source_line + 1))
    nw_compiled=
    nw_last=yes
    printf '%s\n' "$nw_line" > "$nw_work/last"
    nw_run_native "$nw_line"
    if [ -n "$nw_interrupted" ]; then nw_native_status=130; continue; fi
    if [ "$nw_native_status" -eq 0 ] || [ "$nw_strictness" = 2 ] || [ "$nw_mode" = l ]; then continue; fi
    if [ "$nw_strictness" = 1 ] && [ "$nw_source_invalid" = no ]; then
        case "$nw_language:$nw_native_status" in nsh:126|nsh:127) ;; *) continue ;; esac
    fi
    nw_original=$nw_line
    {
        printf 'Directory: %s\nSource line: %s\nNative status: %s\nDiagnostic:\n' "$PWD" "$nw_source_line" "$nw_native_status"
        tail -c 4096 "$nw_work/error"
    } > "$nw_work/context"
    nw_reply "$nw_original"
    nw_native_status=$?
done
