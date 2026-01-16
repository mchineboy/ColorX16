%import textio
%import diskio
%import syslib
%import strings
%import conv
%import session
%import login

; Message boards module
; Handles message boards, reading, posting, and managing messages
; Uses REL files for message storage

boards {

    const ubyte REL_CHANNEL = 3
    const ubyte REL_DEVICE = 8
    const ubyte REL_SECONDARY = 0
    uword REL_FILENAME = "bbsmsgs"
    
    ; Message record structure (fixed length for REL file)
    const ubyte MSG_RECORD_SIZE = 128  ; Fixed record size
    const ubyte MSG_BOARD_MAX = 10     ; Maximum board name length
    const ubyte MSG_AUTHOR_MAX = 20    ; Maximum author name length
    const ubyte MSG_SUBJECT_MAX = 40   ; Maximum subject length
    const ubyte MSG_BODY_MAX = 60      ; Maximum body length (truncated if longer)
    
    ; Record layout:
    ; Offset 0-9: Board name (10 bytes, null-terminated)
    ; Offset 10-29: Author (20 bytes, null-terminated)
    ; Offset 30-69: Subject (40 bytes, null-terminated)
    ; Offset 70-129: Message body (60 bytes, null-terminated)
    ; Offset 130-131: Message ID (2 bytes, uword)
    ; Offset 132-133: Reply to ID (2 bytes, uword, 0 = no reply)
    ; Offset 134: Flags (1 byte: bit 0=active, bit 1=sticky, etc.)
    ; Offset 135-127: Reserved
    
    ubyte @shared boards_initialized = false
    uword @shared max_messages = 500  ; Maximum number of messages
    
    ; Initialize message boards system
    sub init() -> bool {
        diskio.drivenumber = REL_DEVICE
        
        ; Check if REL file exists
        if not diskio.exists(REL_FILENAME) {
            ; Create new REL file
            txt.print("Creating message boards database...")
            txt.nl()
            
            ; Use CBM KERNAL to create REL file
            cbm.SETLFS(REL_CHANNEL, REL_DEVICE, REL_SECONDARY)
            
            ; SETNAM: filename with REL parameters
            ; Format: "filename,L,record_length,R,max_records"
            uword rel_filename = "bbsmsgs,L,128,R,500"
            ubyte rel_filename_len = strings.length(rel_filename)
            cbm.SETNAM(rel_filename_len, rel_filename)
            
            ; OPEN the REL file
            cbm.OPEN()
            
            ubyte status = cbm.READST()
            if status != 0 {
                txt.print("Error creating message boards file: ")
                txt.print_ub(status)
                txt.nl()
                return false
            }
            
            ; Close the file
            cbm.CLOSE(REL_CHANNEL)
            cbm.CLRCHN()
            
            txt.print("Message boards database created successfully")
            txt.nl()
        }
        
        boards_initialized = 1
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
    
    ; Get next message ID
    sub get_next_message_id() -> uword {
        ubyte[MSG_RECORD_SIZE] msg_buffer
        uword max_id = 0
        ubyte i = 0
        
        while i < max_messages {
            if read_message(i, &msg_buffer) {
                if msg_buffer[0] != 0 {  ; Active message
                    ; Extract message ID (offset 130-131)
                    uword msg_id = @(&msg_buffer + 130) | (@(&msg_buffer + 131) << 8)
                    if msg_id > max_id {
                        max_id = msg_id
                    }
                }
            }
            i++
        }
        
        return max_id + 1
    }
    
    ; List messages in a board
    sub list_messages(uword board_name) {
        session.send_line("")
        session.send_line("=== Message Board ===")
        session.send_string("Board: ")
        session.send_string(board_name)
        session.send_line("")
        session.send_line("")
        
        ubyte[MSG_RECORD_SIZE] msg_buffer
        ubyte count = 0
        ubyte i = 0
        
        ; Count messages in this board
        while i < max_messages {
            if read_message(i, &msg_buffer) {
                if msg_buffer[0] != 0 {  ; Active message
                    ; Check board name
                    bool match = true
                    ubyte j = 0
                    while j < MSG_BOARD_MAX {
                        ubyte rec_char = msg_buffer[j]
                        ubyte brd_char = @(board_name + j)
                        
                        if rec_char == 0 and brd_char == 0 {
                            break
                        }
                        if rec_char != brd_char {
                            match = false
                            break
                        }
                        j++
                    }
                    
                    if match {
                        count++
                    }
                }
            }
            i++
        }
        
        if count == 0 {
            session.send_line("No messages in this board.")
            session.send_line("")
            return
        }
        
        session.send_string("Messages: ")
        uword count_str = conv.str_ub(count)
        session.send_string(count_str)
        session.send_line("")
        session.send_line("")
        
        ; Display messages
        i = 0
        ubyte displayed = 0
        while i < max_messages and displayed < 20 {  ; Limit to 20 messages
            if read_message(i, &msg_buffer) {
                if msg_buffer[0] != 0 {
                    ; Check board name
                    bool match2 = true
                    ubyte j2 = 0
                    while j2 < MSG_BOARD_MAX {
                        ubyte rec_char2 = msg_buffer[j2]
                        ubyte brd_char2 = @(board_name + j2)
                        
                        if rec_char2 == 0 and brd_char2 == 0 {
                            break
                        }
                        if rec_char2 != brd_char2 {
                            match2 = false
                            break
                        }
                        j2++
                    }
                    
                    if match2 {
                        ; Extract message info
                        uword msg_id = @(&msg_buffer + 130) | (@(&msg_buffer + 131) << 8)
                        uword subject = &msg_buffer + 30
                        uword author = &msg_buffer + 10
                        
                        ; Display message header
                        session.send_string("[")
                        uword id_str = conv.str_uw(msg_id)
                        session.send_string(id_str)
                        session.send_string("] ")
                        session.send_string(subject)
                        session.send_string(" by ")
                        session.send_string(author)
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
    sub read_message_by_id(uword msg_id) -> bool {
        ubyte[MSG_RECORD_SIZE] msg_buffer
        ubyte i = 0
        
        while i < max_messages {
            if read_message(i, &msg_buffer) {
                if msg_buffer[0] != 0 {
                    uword id = @(&msg_buffer + 130) | (@(&msg_buffer + 131) << 8)
                    if id == msg_id {
                        ; Display message
                        session.send_line("")
                        session.send_line("=== Message ===")
                        session.send_line("")
                        
                        uword subject = &msg_buffer + 30
                        uword author = &msg_buffer + 10
                        uword body = &msg_buffer + 70
                        
                        session.send_string("Subject: ")
                        session.send_string(subject)
                        session.send_line("")
                        session.send_string("From: ")
                        session.send_string(author)
                        session.send_line("")
                        session.send_line("")
                        session.send_string(body)
                        session.send_line("")
                        session.send_line("")
                        
                        return true
                    }
                }
            }
            i++
        }
        
        return false
    }
    
    ; Post a new message
    sub post_message(uword board_name, uword subject, uword body, uword reply_to_id) -> bool {
        ubyte record_num = find_free_message()
        if record_num == 255 {
            session.send_line("Error: Message database full!")
            return false
        }
        
        uword username = login.get_username()
        uword msg_id = get_next_message_id()
        
        ; Create message record
        ubyte[MSG_RECORD_SIZE] msg_buffer
        
        ; Clear record
        ubyte i = 0
        while i < MSG_RECORD_SIZE {
            msg_buffer[i] = 0
            i++
        }
        
        ; Copy board name
        ubyte board_len = strings.length(board_name)
        if board_len > MSG_BOARD_MAX {
            board_len = MSG_BOARD_MAX
        }
        i = 0
        while i < board_len {
            msg_buffer[i] = @(board_name + i)
            i++
        }
        
        ; Copy author
        ubyte author_len = strings.length(username)
        if author_len > MSG_AUTHOR_MAX {
            author_len = MSG_AUTHOR_MAX
        }
        i = 0
        while i < author_len {
            msg_buffer[10 + i] = @(username + i)
            i++
        }
        
        ; Copy subject
        ubyte subject_len = strings.length(subject)
        if subject_len > MSG_SUBJECT_MAX {
            subject_len = MSG_SUBJECT_MAX
        }
        i = 0
        while i < subject_len {
            msg_buffer[30 + i] = @(subject + i)
            i++
        }
        
        ; Copy body
        ubyte body_len = strings.length(body)
        if body_len > MSG_BODY_MAX {
            body_len = MSG_BODY_MAX
        }
        i = 0
        while i < body_len {
            msg_buffer[70 + i] = @(body + i)
            i++
        }
        
        ; Set message ID
        @(&msg_buffer + 130) = lsb(msg_id)
        @(&msg_buffer + 131) = msb(msg_id)
        
        ; Set reply to ID
        @(&msg_buffer + 132) = lsb(reply_to_id)
        @(&msg_buffer + 133) = msb(reply_to_id)
        
        ; Message ID is at offset 126-127, no room for flags in 128-byte record
        
        ; Write record
        if write_message(record_num, &msg_buffer) {
            session.send_line("Message posted successfully!")
            return true
        }
        
        return false
    }
    
    ; Main message boards menu
    sub show_menu() {
        bool running = true
        
        while running and session.is_active() {
            session.send_line("")
            session.send_line("=== Message Boards ===")
            session.send_line("")
            session.send_line("1. General Discussion")
            session.send_line("2. Announcements")
            session.send_line("3. Help & Support")
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
                    show_board("General")
                }
                else if choice == 2 {
                    show_board("Announce")
                }
                else if choice == 3 {
                    show_board("Help")
                }
                else {
                    session.send_line("Invalid choice.")
                }
            } else {
                running = false
            }
        }
    }
    
    ; Show a specific board
    sub show_board(uword board_name) {
        bool running = true
        
        while running and session.is_active() {
            list_messages(board_name)
            
            session.send_line("Options:")
            session.send_line("1. Read message")
            session.send_line("2. Post new message")
            session.send_line("3. Reply to message")
            session.send_line("")
            session.send_line("0. Back to boards")
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
                    ; Read message
                    session.send_string("Enter message ID: ")
                    if session.read_line() {
                        uword id_input = session.get_input_line()
                        uword msg_id = conv.str2uword(id_input)
                        if not read_message_by_id(msg_id) {
                            session.send_line("Message not found.")
                        }
                    }
                }
                else if choice == 2 {
                    ; Post new message
                    session.send_string("Subject: ")
                    if session.read_line() {
                        uword subject = session.get_input_line()
                        session.send_string("Message: ")
                        if session.read_line() {
                            uword body = session.get_input_line()
                            post_message(board_name, subject, body, 0)
                        }
                    }
                }
                else if choice == 3 {
                    ; Reply to message
                    session.send_string("Reply to message ID: ")
                    if session.read_line() {
                        uword reply_id_input = session.get_input_line()
                        uword reply_id = conv.str2uword(reply_id_input)
                        session.send_string("Subject: ")
                        if session.read_line() {
                            uword subject2 = session.get_input_line()
                            session.send_string("Message: ")
                            if session.read_line() {
                                uword body2 = session.get_input_line()
                                post_message(board_name, subject2, body2, reply_id)
                            }
                        }
                    }
                }
            } else {
                running = false
            }
        }
    }

}
