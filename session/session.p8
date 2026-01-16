%import textio
%import com/com
%import config/config
%import strings
%import login/login
%import conv
%import menu/menu

; Session management module for BBS
; Handles user sessions, terminal interactions, and basic event loop

session {

    ubyte @shared session_active = false
    uword @shared session_start_time = 0
    uword @shared bytes_received = 0
    uword @shared bytes_sent = 0
    
    ; Session states
    const ubyte STATE_WAITING = 0
    const ubyte STATE_CONNECTED = 1
    const ubyte STATE_LOGIN = 2
    const ubyte STATE_MENU = 3
    const ubyte STATE_DISCONNECTED = 4
    
    ubyte @shared current_state = STATE_WAITING
    
    ; Input buffer for user input
    ubyte[256] input_buffer
    ubyte input_pos = 0
    
    ; Initialize session system
    sub init() {
        session_active = false
        current_state = STATE_WAITING
        input_pos = 0
        bytes_received = 0
        bytes_sent = 0
    }
    
    ; Wait for a connection
    ; Returns true when connection detected, false on timeout or error
    sub wait_for_connection() -> bool {
        txt.print("Waiting for connection...")
        txt.nl()
        
        ; Poll for incoming data (connection indicator)
        uword timeout = 0
        while timeout < 18000 {  ; 5 minutes (60 jiffies per second * 60 * 5)
            if com.data_available() {
                ; Data available - connection detected
                session_active = true
                current_state = STATE_CONNECTED
                session_start_time = 0  ; TODO: Use actual system time when available
                txt.print("Connection detected!")
                txt.nl()
                return true
            }
            
            ; Small delay to avoid busy-waiting
            wait(6)  ; 0.1 second
            timeout = timeout + 6
        }
        
        ; Timeout
        txt.print("Connection timeout")
        txt.nl()
        return false
    }
    
    ; Send greeting to connected user
    sub send_greeting() {
        uword bbs_name = config.getdirective("bbsname")
        if len(bbs_name) == 0 {
            bbs_name = "ColorX128 BBS"
        }
        
        ; Send welcome message
        com.write_char($0d)  ; Carriage return
        com.write_char($0a)  ; Line feed
        com.write_str("Welcome to ")
        com.write_str(bbs_name)
        com.write_str("!")
        com.write_char($0d)
        com.write_char($0a)
        com.write_char($0d)
        com.write_char($0a)
    }
    
    ; Read a line from the serial connection
    ; Handles backspace, echo, and line termination
    ; Returns: true if line received, false on disconnect
    sub read_line() -> bool {
        input_pos = 0
        input_buffer[0] = 0
        
        while input_pos < 255 {
            if not com.data_available() {
                ; No data yet, small delay
                wait(1)
                continue
            }
            
            ubyte ch = com.read_char()
            
            if ch == 0 {
                ; Error or no data
                wait(1)
                continue
            }
            
            bytes_received++
            
            ; Handle special characters
            if ch == $08 or ch == $7f {  ; Backspace or DEL
                if input_pos > 0 {
                    input_pos--
                    input_buffer[input_pos] = 0
                    ; Echo backspace sequence
                    com.write_char($08)  ; Backspace
                    com.write_char($20)  ; Space
                    com.write_char($08)  ; Backspace again
                }
                continue
            }
            
            if ch == $0d or ch == $0a {  ; Carriage return or line feed
                ; Line complete
                input_buffer[input_pos] = 0
                com.write_char($0d)
                com.write_char($0a)
                return true
            }
            
            ; Regular character
            if ch >= $20 and ch <= $7e {  ; Printable ASCII
                input_buffer[input_pos] = ch
                input_pos++
                input_buffer[input_pos] = 0
                
                ; Echo character
                com.write_char(ch)
            }
        }
        
        ; Buffer full
        return true
    }
    
    ; Get the current input line
    sub get_input_line() -> uword {
        return &input_buffer[0]
    }
    
    ; Send a line to the user
    sub send_line(uword line) {
        com.write_str(line)
        com.write_char($0d)
        com.write_char($0a)
        bytes_sent = bytes_sent + strings.length(line) + 2
    }
    
    ; Send a string (no line ending)
    sub send_string(uword str_ptr) {
        com.write_str(str_ptr)
        bytes_sent = bytes_sent + strings.length(str_ptr)
    }
    
    ; Check if session is still active
    sub is_active() -> bool {
        if not session_active {
            return false
        }
        
        ; Check for disconnect (no data available and status indicates disconnect)
        ubyte status = com.get_status()
        if status != 0 and (status & $40) == 0 {
            ; Error status (not just EOF)
            return false
        }
        
        return true
    }
    
    ; Handle a user session
    ; Main session loop - handles connection, login, basic interaction, disconnect
    sub handle_session() {
        current_state = STATE_CONNECTED
        
        ; Send greeting
        send_greeting()
        
        ; Require login
        current_state = STATE_LOGIN
        if not login.prompt_login() {
            ; Login failed or user disconnected
            send_line("Login failed. Disconnecting...")
            session_active = false
            current_state = STATE_DISCONNECTED
            return
        }
        
        ; Login successful - show welcome
        current_state = STATE_MENU
        send_line("")
        uword username = login.get_username()
        send_string("Welcome, ")
        send_string(username)
        send_line("!")
        send_line("")
        
        ; Show BBS info
        menu.show_info()
        
        ; Run main menu system
        menu.run()
        
        ; Session ended
        send_line("")
        send_line("Connection closed.")
        session_active = false
        current_state = STATE_DISCONNECTED
    }
    
    ; Get session statistics
    sub get_bytes_received() -> uword {
        return bytes_received
    }
    
    sub get_bytes_sent() -> uword {
        return bytes_sent
    }
    
    sub get_session_time() -> uword {
        if not session_active {
            return 0
        }
        ; TODO: Calculate actual session time when system time available
        return 0
    }

}
