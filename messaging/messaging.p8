%import textio
%import diskio
%import syslib
%import strings
%import conv
%import session/session
%import login/login

; Private messaging/email module
; Handles private messages between users
; Uses REL files for message storage

messaging {

    const ubyte REL_CHANNEL = 4
    const ubyte REL_DEVICE = 8
    const ubyte REL_SECONDARY = 0
    uword REL_FILENAME = "bbsmail"
    
    ; Message record structure (fixed length for REL file)
    const ubyte MSG_RECORD_SIZE = 128  ; Fixed record size
    const ubyte MSG_TO_MAX = 20        ; Maximum recipient name length
    const ubyte MSG_FROM_MAX = 20      ; Maximum sender name length
    const ubyte MSG_SUBJECT_MAX = 40   ; Maximum subject length
    const ubyte MSG_BODY_MAX = 48      ; Maximum body length
    
    ; Record layout:
    ; Offset 0-19: To (recipient, 20 bytes, null-terminated)
    ; Offset 20-39: From (sender, 20 bytes, null-terminated)
    ; Offset 40-79: Subject (40 bytes, null-terminated)
    ; Offset 80-127: Message body (48 bytes, null-terminated)
    ; Note: We'll use the last byte as flags (read/unread, deleted)
    
    ubyte @shared messaging_initialized = 0
    uword @shared max_messages = 1000  ; Maximum number of messages
    
    ; Initialize messaging system
    sub init() -> bool {
        diskio.drivenumber = REL_DEVICE
        
        ; Check if REL file exists
        if not diskio.exists(REL_FILENAME) {
            ; Create new REL file
            txt.print("Creating messaging database...")
            txt.nl()
            
            ; Use CBM KERNAL to create REL file
            cbm.SETLFS(REL_CHANNEL, REL_DEVICE, REL_SECONDARY)
            
            ; SETNAM: filename with REL parameters
            uword rel_filename = "bbsmail,L,128,R,1000"
            ubyte rel_filename_len = strings.length(rel_filename)
            cbm.SETNAM(rel_filename_len, rel_filename)
            
            ; OPEN the REL file
            cbm.OPEN()
            
            ubyte status = cbm.READST()
            if status != 0 {
                txt.print("Error creating messaging file: ")
                txt.print_ub(status)
                txt.nl()
                return false
            }
            
            ; Close the file
            cbm.CLOSE(REL_CHANNEL)
            cbm.CLRCHN()
            
            txt.print("Messaging database created successfully")
            txt.nl()
        }
        
        messaging_initialized = true
        return true
    }
    
    ; Open REL file for reading/writing
    sub open_rel() -> bool {
        cbm.SETLFS(REL_CHANNEL, REL_DEVICE, REL_SECONDARY)
        cbm.SETNAM(strings.length(REL_FILENAME), REL_FILENAME)
        cbm.OPEN()
        
        ubyte status = cbm.READST()
        if status != 0 {
            return false
        }
        
        return true
    }
    
    ; Close REL file
    sub close_rel() {
        cbm.CLOSE(REL_CHANNEL)
        cbm.CLRCHN()
    }
    
    ; Position to a specific record in REL file
    sub seek_record(ubyte record_num) -> bool {
        cbm.CHKOUT(REL_CHANNEL)
        
        ; Send RECORD command
        cbm.CHROUT($52)  ; 'R'
        cbm.CHROUT($23)  ; '#'
        cbm.CHROUT(REL_CHANNEL + $30)
        cbm.CHROUT($2c)  ; ','
        
        ; Send record number
        uword rec_str = conv.str_ub(record_num)
        uword i = 0
        while i < strings.length(rec_str) {
            cbm.CHROUT(@(rec_str + i))
            i++
        }
        
        cbm.CHROUT($0d)
        
        ubyte status = cbm.READST()
        cbm.CLRCHN()
        
        return status == 0
    }
    
    ; Read a message record from REL file
    sub read_message(ubyte record_num, uword buffer) -> bool {
        if not open_rel() {
            return false
        }
        
        if not seek_record(record_num) {
            close_rel()
            return false
        }
        
        cbm.CHKIN(REL_CHANNEL)
        
        uword i = 0
        while i < MSG_RECORD_SIZE {
            ubyte ch = cbm.CHRIN()
            @(buffer + i) = ch
            i++
        }
        
        cbm.CLRCHN()
        close_rel()
        
        return true
    }
    
    ; Write a message record to REL file
    sub write_message(ubyte record_num, uword buffer) -> bool {
        if not open_rel() {
            return false
        }
        
        if not seek_record(record_num) {
            close_rel()
            return false
        }
        
        cbm.CHKOUT(REL_CHANNEL)
        
        uword i = 0
        while i < MSG_RECORD_SIZE {
            cbm.CHROUT(@(buffer + i))
            i++
        }
        
        cbm.CLRCHN()
        close_rel()
        
        return true
    }
    
    ; Find first free message record
    sub find_free_message() -> ubyte {
        ubyte[MSG_RECORD_SIZE] msg_buffer
        ubyte i = 0
        
        while i < max_messages {
            if read_message(i, &msg_buffer) {
                ; Check if record is empty (first byte == 0)
                if msg_buffer[0] == 0 {
                    return i
                }
            }
            i++
        }
        
        return 255  ; No free records
    }
    
    ; Count messages for a user (inbox)
    sub count_inbox(uword username) -> ubyte {
        ubyte[MSG_RECORD_SIZE] msg_buffer
        ubyte count = 0
        ubyte i = 0
        
        while i < max_messages {
            if read_message(i, &msg_buffer) {
                if msg_buffer[0] != 0 {  ; Active message
                    ; Check if message is to this user
                    bool match = true
                    uword j = 0
                    while j < MSG_TO_MAX {
                        ubyte rec_char = msg_buffer[j]
                        ubyte usr_char = @(username + j)
                        
                        if rec_char == 0 and usr_char == 0 {
                            break
                        }
                        if rec_char != usr_char {
                            match = false
                            break
                        }
                        j++
                    }
                    
                    if match {
                        ; Check if not deleted (flag byte at 127)
                        if (msg_buffer[127] & $02) == 0 {
                            count++
                        }
                    }
                }
            }
            i++
        }
        
        return count
    }
    
    ; Count unread messages for a user
    sub count_unread(uword username) -> ubyte {
        ubyte[MSG_RECORD_SIZE] msg_buffer
        ubyte count = 0
        ubyte i = 0
        
        while i < max_messages {
            if read_message(i, &msg_buffer) {
                if msg_buffer[0] != 0 {
                    ; Check if message is to this user
                    bool match = true
                    uword j = 0
                    while j < MSG_TO_MAX {
                        ubyte rec_char = msg_buffer[j]
                        ubyte usr_char = @(username + j)
                        
                        if rec_char == 0 and usr_char == 0 {
                            break
                        }
                        if rec_char != usr_char {
                            match = false
                            break
                        }
                        j++
                    }
                    
                    if match {
                        ; Check if unread (flag byte at 127, bit 0 = read)
                        if (msg_buffer[127] & $01) == 0 and (msg_buffer[127] & $02) == 0 {
                            count++
                        }
                    }
                }
            }
            i++
        }
        
        return count
    }
    
    ; List messages in inbox
    sub list_inbox(uword username) {
        session.send_line("")
        session.send_line("=== Inbox ===")
        session.send_line("")
        
        ubyte unread = count_unread(username)
        ubyte total = count_inbox(username)
        
        session.send_string("Messages: ")
        uword total_str = conv.str_ub(total)
        session.send_string(total_str)
        session.send_string(" (")
        uword unread_str = conv.str_ub(unread)
        session.send_string(unread_str)
        session.send_string(" unread)")
        session.send_line("")
        session.send_line("")
        
        if total == 0 {
            session.send_line("No messages.")
            session.send_line("")
            return
        }
        
        ubyte[MSG_RECORD_SIZE] msg_buffer
        ubyte displayed = 0
        ubyte i = 0
        
        while i < max_messages and displayed < 20 {
            if read_message(i, &msg_buffer) {
                if msg_buffer[0] != 0 {
                    ; Check if message is to this user
                    bool match = true
                    uword j = 0
                    while j < MSG_TO_MAX {
                        ubyte rec_char = msg_buffer[j]
                        ubyte usr_char = @(username + j)
                        
                        if rec_char == 0 and usr_char == 0 {
                            break
                        }
                        if rec_char != usr_char {
                            match = false
                            break
                        }
                        j++
                    }
                    
                    if match and (msg_buffer[127] & $02) == 0 {  ; Not deleted
                        ; Display message header
                        uword from = &msg_buffer + 20
                        uword subject = &msg_buffer + 40
                        
                        ; Show unread indicator
                        if (msg_buffer[127] & $01) == 0 {
                            session.send_string("* ")  ; Unread
                        } else {
                            session.send_string("  ")  ; Read
                        }
                        
                        session.send_string("[")
                        uword num_str = conv.str_ub(i)
                        session.send_string(num_str)
                        session.send_string("] ")
                        session.send_string(subject)
                        session.send_string(" from ")
                        session.send_string(from)
                        session.send_line("")
                        
                        displayed++
                    }
                }
            }
            i++
        }
        
        session.send_line("")
    }
    
    ; Read a specific message
    sub read_message_by_num(ubyte msg_num, uword username) -> bool {
        ubyte[MSG_RECORD_SIZE] msg_buffer
        
        if not read_message(msg_num, &msg_buffer) {
            return false
        }
        
        if msg_buffer[0] == 0 {
            return false  ; Empty record
        }
        
        ; Check if message is to this user
        bool match = true
        uword j = 0
        while j < MSG_TO_MAX {
            ubyte rec_char = msg_buffer[j]
            ubyte usr_char = @(username + j)
            
            if rec_char == 0 and usr_char == 0 {
                break
            }
            if rec_char != usr_char {
                match = false
                break
            }
            j++
        }
        
        if not match {
            return false  ; Not for this user
        }
        
        ; Display message
        session.send_line("")
        session.send_line("=== Message ===")
        session.send_line("")
        
        uword from = &msg_buffer + 20
        uword subject = &msg_buffer + 40
        uword body = &msg_buffer + 80
        
        session.send_string("From: ")
        session.send_string(from)
        session.send_line("")
        session.send_string("Subject: ")
        session.send_string(subject)
        session.send_line("")
        session.send_line("")
        session.send_string(body)
        session.send_line("")
        session.send_line("")
        
        ; Mark as read
        msg_buffer[127] = msg_buffer[127] | $01  ; Set read bit
        write_message(msg_num, &msg_buffer)
        
        return true
    }
    
    ; Send a message
    sub send_message(uword to_username, uword subject, uword body) -> bool {
        ubyte record_num = find_free_message()
        if record_num == 255 {
            session.send_line("Error: Message database full!")
            return false
        }
        
        uword from_username = login.get_username()
        
        ; Create message record
        ubyte[MSG_RECORD_SIZE] msg_buffer
        
        ; Clear record
        uword i = 0
        while i < MSG_RECORD_SIZE {
            msg_buffer[i] = 0
            i++
        }
        
        ; Copy recipient
        ubyte to_len = strings.length(to_username)
        if to_len > MSG_TO_MAX {
            to_len = MSG_TO_MAX
        }
        i = 0
        while i < to_len {
            msg_buffer[i] = @(to_username + i)
            i++
        }
        
        ; Copy sender
        ubyte from_len = strings.length(from_username)
        if from_len > MSG_FROM_MAX {
            from_len = MSG_FROM_MAX
        }
        i = 0
        while i < from_len {
            msg_buffer[20 + i] = @(from_username + i)
            i++
        }
        
        ; Copy subject
        ubyte subject_len = strings.length(subject)
        if subject_len > MSG_SUBJECT_MAX {
            subject_len = MSG_SUBJECT_MAX
        }
        i = 0
        while i < subject_len {
            msg_buffer[40 + i] = @(subject + i)
            i++
        }
        
        ; Copy body
        ubyte body_len = strings.length(body)
        if body_len > MSG_BODY_MAX {
            body_len = MSG_BODY_MAX
        }
        i = 0
        while i < body_len {
            msg_buffer[80 + i] = @(body + i)
            i++
        }
        
        ; Set flags (unread, not deleted)
        msg_buffer[127] = $00
        
        ; Write record
        if write_message(record_num, &msg_buffer) {
            session.send_line("Message sent successfully!")
            return true
        }
        
        return false
    }
    
    ; Delete a message
    sub delete_message(ubyte msg_num, uword username) -> bool {
        ubyte[MSG_RECORD_SIZE] msg_buffer
        
        if not read_message(msg_num, &msg_buffer) {
            return false
        }
        
        ; Check if message is to this user
        bool match = true
        uword j = 0
        while j < MSG_TO_MAX {
            ubyte rec_char = msg_buffer[j]
            ubyte usr_char = @(username + j)
            
            if rec_char == 0 and usr_char == 0 {
                break
            }
            if rec_char != usr_char {
                match = false
                break
            }
            j++
        }
        
        if not match {
            return false
        }
        
        ; Mark as deleted
        msg_buffer[127] = msg_buffer[127] | $02  ; Set deleted bit
        return write_message(msg_num, &msg_buffer)
    }
    
    ; Main messaging menu
    sub show_menu() {
        bool running = true
        uword username = login.get_username()
        
        while running and session.is_active() {
            session.send_line("")
            session.send_line("=== Private Messages ===")
            session.send_line("")
            session.send_line("1. Read Inbox")
            session.send_line("2. Send Message")
            session.send_line("3. Delete Message")
            session.send_line("")
            session.send_line("0. Return to Main Menu")
            session.send_line("")
            session.send_string("Enter choice: ")
            
            if session.read_line() {
                uword input = session.get_input_line()
                
                if strings.length(input) == 0 {
                    continue
                }
                
                ubyte choice = @(input)
                if choice >= $30 and choice <= $39 {
                    choice = choice - $30
                } else {
                    session.send_line("Invalid choice.")
                    continue
                }
                
                if choice == 0 {
                    running = false
                }
                else if choice == 1 {
                    ; Read inbox
                    list_inbox(username)
                    session.send_string("Enter message number to read (or 0 to go back): ")
                    if session.read_line() {
                        uword num_input2 = session.get_input_line()
                        ubyte msg_num2 = conv.str2ubyte(num_input2)
                        if msg_num2 != 0 {
                            if not read_message_by_num(msg_num2, username) {
                                session.send_line("Message not found or access denied.")
                            }
                        }
                    }
                }
                else if choice == 2 {
                    ; Send message
                    session.send_string("To: ")
                    if session.read_line() {
                        uword to_user = session.get_input_line()
                        session.send_string("Subject: ")
                        if session.read_line() {
                            uword subject = session.get_input_line()
                            session.send_string("Message: ")
                            if session.read_line() {
                                uword body = session.get_input_line()
                                send_message(to_user, subject, body)
                            }
                        }
                    }
                }
                else if choice == 3 {
                    ; Delete message
                    list_inbox(username)
                    session.send_string("Enter message number to delete (or 0 to cancel): ")
                    if session.read_line() {
                        uword num_input = session.get_input_line()
                        ubyte msg_num = conv.str2ubyte(num_input)
                        if msg_num != 0 {
                            if delete_message(msg_num, username) {
                                session.send_line("Message deleted.")
                            } else {
                                session.send_line("Error deleting message.")
                            }
                        }
                    }
                }
                else {
                    session.send_line("Invalid choice.")
                }
            } else {
                running = false
            }
        }
    }

}
