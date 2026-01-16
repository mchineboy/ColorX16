%import textio
%import session
%import login
%import config
%import strings
%import conv
%import boards
%import messaging
%import files

; Main menu and navigation system for BBS
; Provides menu-driven interface for accessing BBS features

menu {

    ; Menu states
    const ubyte MENU_MAIN = 0
    const ubyte MENU_BOARDS = 1
    const ubyte MENU_MESSAGING = 2
    const ubyte MENU_FILES = 3
    const ubyte MENU_GAMES = 4
    const ubyte MENU_SYSOP = 5
    
    ubyte @shared current_menu = MENU_MAIN
    
    ; Display main menu
    sub show_main_menu() {
        session.send_line("")
        session.send_line("=== Main Menu ===")
        session.send_line("")
        session.send_line("1. Message Boards")
        session.send_line("2. Private Messages")
        session.send_line("3. File Areas")
        session.send_line("4. Games")
        
        ; Check user level for sysop menu
        ubyte user_level = login.get_user_level()
        if user_level >= 7 {  ; Administrator or SysOp
            session.send_line("5. SysOp Functions")
        }
        
        session.send_line("")
        session.send_line("0. Logout")
        session.send_line("")
        session.send_string("Enter choice: ")
    }
    
    ; Process menu selection
    ; Returns true if should continue, false if logout/disconnect
    sub process_selection(uword input) -> bool {
        if strings.length(input) == 0 {
            return true
        }
        
        ; Get first character as menu choice
        ubyte choice = @(input)
        if choice >= $30 and choice <= $39 {  ; ASCII '0'-'9'
            choice = choice - $30  ; Convert to number
        } else {
            session.send_line("Invalid choice. Please enter a number.")
            return true
        }
        
        ubyte user_level = login.get_user_level()
        
        ; Route to appropriate menu/function
        if choice == 0 {
            ; Logout
            session.send_line("Logging out...")
            login.logout()
            return false
        }
        else if choice == 1 {
            ; Message Boards
            show_boards_menu()
        }
        else if choice == 2 {
            ; Private Messages
            show_messaging_menu()
        }
        else if choice == 3 {
            ; File Areas
            show_files_menu()
        }
        else if choice == 4 {
            ; Games
            show_games_menu()
        }
        else if choice == 5 and user_level >= 7 {
            ; SysOp Functions
            show_sysop_menu()
        }
        else {
            session.send_line("Invalid choice.")
        }
        
        return true
    }
    
    ; Show message boards menu
    sub show_boards_menu() {
        boards.show_menu()
    }
    
    ; Show messaging menu
    sub show_messaging_menu() {
        messaging.show_menu()
    }
    
    ; Show file areas menu
    sub show_files_menu() {
        files.show_menu()
    }
    
    ; Show games menu (placeholder)
    sub show_games_menu() {
        session.send_line("")
        session.send_line("=== Games ===")
        session.send_line("")
        session.send_line("Games are not yet implemented.")
        session.send_line("")
        session.send_string("Press Enter to continue...")
        session.read_line()
    }
    
    ; Show sysop menu (placeholder)
    sub show_sysop_menu() {
        session.send_line("")
        session.send_line("=== SysOp Functions ===")
        session.send_line("")
        session.send_line("SysOp functions are not yet implemented.")
        session.send_line("")
        session.send_string("Press Enter to continue...")
        session.read_line()
    }
    
    ; Main menu loop
    ; Handles menu display and navigation
    sub run() {
        bool running = true
        
        while running and session.is_active() {
            ; Show main menu
            show_main_menu()
            
            ; Read user input
            if session.read_line() {
                uword input = session.get_input_line()
                
                ; Process selection
                if not process_selection(input) {
                    ; Logout requested
                    running = false
                    break
                }
            } else {
                ; Read failed - disconnect
                running = false
                break
            }
        }
    }
    
    ; Show BBS information
    sub show_info() {
        session.send_line("")
        session.send_line("=== BBS Information ===")
        session.send_line("")
        
        uword bbs_name = config.getdirective("bbsname")
        if strings.length(bbs_name) == 0 {
            bbs_name = "ColorX128 BBS"
        }
        session.send_string("BBS Name: ")
        session.send_string(bbs_name)
        session.send_line("")
        
        uword sysop_name = config.getdirective("sysopname")
        if strings.length(sysop_name) == 0 {
            sysop_name = "SysOp"
        }
        session.send_string("SysOp: ")
        session.send_string(sysop_name)
        session.send_line("")
        
        session.send_line("Status: Online")
        session.send_line("")
        
        uword username = login.get_username()
        ubyte level = login.get_user_level()
        session.send_string("Logged in as: ")
        session.send_string(username)
        session.send_line("")
        session.send_string("User Level: ")
        uword level_str = conv.str_ub(level)
        session.send_string(level_str)
        session.send_line("")
        session.send_line("")
    }

}
