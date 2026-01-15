%import textio
%import userdb/userdb
%import session/session
%import strings
%import conv

; Login/authentication module for BBS
; Handles user login, authentication, and session management

login {

    ubyte @shared current_user_level = 0
    uword @shared current_username = ""
    bool @shared logged_in = false
    ubyte @shared login_attempts = 0
    const ubyte MAX_LOGIN_ATTEMPTS = 3
    
    ; Initialize login system
    sub init() {
        current_user_level = 0
        current_username = ""
        logged_in = false
        login_attempts = 0
        
        ; Initialize user database
        if not userdb.init() {
            txt.print("WARNING: Could not initialize user database!")
            txt.nl()
        }
    }
    
    ; Prompt for and handle user login
    ; Returns true if login successful, false otherwise
    sub prompt_login() -> bool {
        logged_in = false
        login_attempts = 0
        
        ; Clear screen (send to remote user)
        session.send_line("")
        session.send_line("=== Login Required ===")
        session.send_line("")
        
        while login_attempts < MAX_LOGIN_ATTEMPTS {
            ; Prompt for username
            session.send_string("Username: ")
            
            if not session.read_line() {
                return false  ; Disconnect
            }
            
            uword username = session.get_input_line()
            
            if strings.length(username) == 0 {
                session.send_line("Username cannot be empty.")
                continue
            }
            
            ; Prompt for password
            session.send_string("Password: ")
            
            ; Note: For password input, we might want to disable echo
            ; For now, we'll use normal input (insecure but functional)
            if not session.read_line() {
                return false  ; Disconnect
            }
            
            uword password = session.get_input_line()
            
            ; Verify credentials
            if userdb.verify_password(username, password) {
                ; Login successful
                current_username = username
                current_user_level = userdb.get_user_level(username)
                logged_in = true
                login_attempts = 0
                
                session.send_line("")
                session.send_line("Login successful!")
                session.send_line("")
                
                return true
            } else {
                ; Login failed
                login_attempts++
                ubyte remaining = MAX_LOGIN_ATTEMPTS - login_attempts
                
                session.send_line("Invalid username or password.")
                if remaining > 0 {
                    session.send_string("Attempts remaining: ")
                    uword rem_str = conv.str_ub(remaining)
                    session.send_string(rem_str)
                    session.send_line("")
                } else {
                    session.send_line("Maximum login attempts exceeded.")
                    session.send_line("Connection terminated.")
                    return false
                }
            }
        }
        
        return false
    }
    
    ; Check if user is logged in
    sub is_logged_in() -> bool {
        return logged_in
    }
    
    ; Get current username
    sub get_username() -> uword {
        return current_username
    }
    
    ; Get current user level
    sub get_user_level() -> ubyte {
        return current_user_level
    }
    
    ; Logout current user
    sub logout() {
        logged_in = false
        current_username = ""
        current_user_level = 0
        login_attempts = 0
    }
    
    ; Create a new user (for setup or sysop functions)
    sub create_user(uword username, uword password, ubyte user_level) -> bool {
        return userdb.add_user(username, password, user_level)
    }

}
