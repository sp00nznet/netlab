# Menu steps for The Simpsons Arcade Game (NPUB30563, ps3recomp), sourced by
# the scenarios here. Menus drop presses that land during a transition, so
# every step retries on the log line that shows it worked.

# From attract mode to the Online Game menu.
online_menu() {
    wait_log "$1" "ManagerGetStatus() -> ONLINE" 120 || return 1
    sleep 8
    for try in 1 2 3; do
        press "$1" $START "" 10
        press "$1" $DOWN 10 3
        press "$1" $CROSS "" 6
        wait_log "$1" "CreateContext(NPWR" 10 && return 0
        press "$1" $CIRCLE "" 4; press "$1" $CIRCLE "" 4     # back out, try again
    done
    return 1
}

# Online Game -> Create Match -> the lobby.
create_match() {
    press "$1" $DOWN 10 3; press "$1" $DOWN 10 3; press "$1" $CROSS "" 6
    for try in 1 2 3 4; do
        press "$1" $CROSS "" 6
        wait_log "$1" "created room" 5 && return 0
    done
    return 1
}

# Online Game -> Quick Match, searching again until a room is joined.
quick_match() {
    for try in 1 2 3 4 5; do press "$1" $CROSS "" 8; wait_log "$1" "SearchRoom" 6 && break; done
    for try in 1 2 3 4; do wait_log "$1" "joined room" 8 && return 0; press "$1" $SQUARE "" 6; done
    wait_log "$1" "joined room" 1
}
