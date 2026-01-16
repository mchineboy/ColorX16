%import textio
%import diskio
%import session/session
%import login/login
%import strings
%import conv
%import com/com

; File transfer module
; Handles file uploads, downloads, and file area management
; Uses diskio for file operations

files {

    ubyte @shared files_initialized = false
    ubyte @shared file_drive = 8
    uword @shared file_area = "files"  ; Default file area directory
    
    ; Initialize file system
    sub init() {
        diskio.drivenumber = file_drive
        files_initialized = true
    }
    
    ; List files in a directory/area
    sub list_files(uword pattern) {
        session.send_line("")
        session.send_line("=== File Listing ===")
        session.send_line("")
        
        diskio.drivenumber = file_drive
        
        ; Start file listing
        if diskio.lf_start_list(pattern) {
            ubyte count = 0
            
            session.send_line("Files:")
            session.send_line("")
            
            while diskio.lf_next_entry() {
                ; Display file information
                session.send_string("[")
                uword blocks_str = conv.str_uw(diskio.list_blocks)
                session.send_string(blocks_str)
                session.send_string("] ")
                session.send_string(diskio.list_filename)
                session.send_string(" (")
                session.send_string(diskio.list_filetype)
                session.send_string(")")
                session.send_line("")
                
                count++
                
                ; Limit display to 50 files
                if count >= 50 {
                    session.send_line("... (more files available)")
                    break
                }
            }
            
            diskio.lf_end_list()
            
            session.send_line("")
            session.send_string("Total: ")
            uword count_str = conv.str_ub(count)
            session.send_string(count_str)
            session.send_line(" files")
        } else {
            session.send_line("Error listing files.")
        }
        
        session.send_line("")
    }
    
    ; Download a file (send file contents to user)
    sub download_file(uword filename) -> bool {
        session.send_line("")
        session.send_string("Downloading: ")
        session.send_string(filename)
        session.send_line("")
        
        diskio.drivenumber = file_drive
        
        ; Check if file exists
        if not diskio.exists(filename) {
            session.send_line("File not found.")
            return false
        }
        
        ; Open file for reading
        if not diskio.f_open(filename) {
            session.send_line("Error opening file.")
            return false
        }
        
        session.send_line("File transfer starting...")
        session.send_line("")
        
        ; Read and send file in chunks
        ubyte[256] buffer
        uword total_bytes = 0
        bool error = false
        
        while true {
            uword bytes_read = diskio.f_read(&buffer[0], 256)
            
            if bytes_read == 0 {
                break  ; EOF
            }
            
            ; Send chunk to user
            uword i = 0
            while i < bytes_read {
                if not com.write_char(buffer[i]) {
                    error = true
                    break
                }
                total_bytes++
                i++
            }
            
            if error {
                break
            }
        }
        
        diskio.f_close()
        
        if error {
            session.send_line("")
            session.send_line("Transfer error occurred.")
            return false
        }
        
        session.send_line("")
        session.send_string("Transfer complete: ")
        uword size_str = conv.str_uw(total_bytes)
        session.send_string(size_str)
        session.send_string(" bytes")
        session.send_line("")
        
        return true
    }
    
    ; Upload a file (receive file from user and save)
    sub upload_file(uword filename, uword max_size) -> bool {
        session.send_line("")
        session.send_string("Upload: ")
        session.send_string(filename)
        session.send_line("")
        session.send_string("Maximum size: ")
        uword max_str = conv.str_uw(max_size)
        session.send_string(max_str)
        session.send_string(" bytes")
        session.send_line("")
        session.send_line("Send file now (or type 'cancel' to abort):")
        session.send_line("")
        
        ; Check user level for upload permission
        ubyte user_level = login.get_user_level()
        if user_level < 2 {  ; Only level 2+ can upload
            session.send_line("Upload permission denied.")
            return false
        }
        
        diskio.drivenumber = file_drive
        
        ; Open file for writing
        if not diskio.f_open_w(filename) {
            session.send_line("Error creating file.")
            return false
        }
        
        session.send_line("Ready to receive file...")
        session.send_line("")
        
        ; Receive file data
        uword bytes_received = 0
        ubyte[256] buffer
        uword buffer_pos = 0
        bool receiving = true
        bool cancelled = false
        
        while receiving and bytes_received < max_size {
            ; Check for incoming data
            if com.data_available() {
                ubyte ch = com.read_char()
                
                if ch == 0 {
                    ; No data or error
                    wait(1)
                    continue
                }
                
                ; Check for cancel command (simple text check)
                if ch == $03 {  ; Ctrl-C
                    cancelled = true
                    break
                }
                
                ; Store byte in buffer
                buffer[buffer_pos] = ch
                buffer_pos++
                bytes_received++
                
                ; Write buffer when full
                if buffer_pos >= 256 {
                    if not diskio.f_write(&buffer[0], 256) {
                        receiving = false
                        break
                    }
                    buffer_pos = 0
                }
                
                ; Echo progress every 1KB
                if (bytes_received & $03FF) == 0 {
                    session.send_string(".")
                }
            } else {
                ; No data available, small delay
                wait(1)
                
                ; Check for timeout (simple: if no data for a while, assume done)
                ; This is a basic implementation - could be improved
            }
        }
        
        ; Write remaining buffer
        if buffer_pos > 0 and not cancelled {
            diskio.f_write(&buffer[0], buffer_pos)
        }
        
        diskio.f_close_w()
        
        if cancelled {
            session.send_line("")
            session.send_line("Upload cancelled.")
            return false
        }
        
        session.send_line("")
        session.send_string("Upload complete: ")
        uword size_str = conv.str_uw(bytes_received)
        session.send_string(size_str)
        session.send_string(" bytes")
        session.send_line("")
        
        return true
    }
    
    ; Show file areas menu
    sub show_menu() {
        bool running = true
        
        while running and session.is_active() {
            session.send_line("")
            session.send_line("=== File Areas ===")
            session.send_line("")
            session.send_line("1. List Files")
            session.send_line("2. Download File")
            session.send_line("3. Upload File")
            session.send_line("")
            session.send_line("0. Return to Main Menu")
            session.send_line("")
            session.send_string("Enter choice: ")
            
            if session.read_line() {
                uword input = session.get_input_line()
                
                if strings.length(input) == 0 {
                    continue
                }
                
                ubyte choice = @input
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
                    ; List files
                    session.send_string("Enter file pattern (or * for all): ")
                    if session.read_line() {
                        uword pattern = session.get_input_line()
                        if strings.length(pattern) == 0 {
                            pattern = "*"
                        }
                        list_files(pattern)
                    }
                }
                else if choice == 2 {
                    ; Download file
                    session.send_string("Enter filename: ")
                    if session.read_line() {
                        uword filename = session.get_input_line()
                        if strings.length(filename) > 0 {
                            download_file(filename)
                        }
                    }
                }
                else if choice == 3 {
                    ; Upload file
                    ubyte user_level = login.get_user_level()
                    if user_level < 2 {
                        session.send_line("Upload permission denied. Level 2+ required.")
                    } else {
                        session.send_string("Enter filename: ")
                        if session.read_line() {
                            uword filename = session.get_input_line()
                            if strings.length(filename) > 0 {
                                uword max_size = 65535  ; 64KB max
                                upload_file(filename, max_size)
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
    
    ; Get file information
    sub get_file_info(uword filename) {
        diskio.drivenumber = file_drive
        
        if not diskio.exists(filename) {
            session.send_line("File not found.")
            return
        }
        
        ; Get file size (approximate from blocks)
        ; This is a simplified version
        session.send_line("")
        session.send_string("File: ")
        session.send_string(filename)
        session.send_line("")
        session.send_line("(File info display not fully implemented)")
        session.send_line("")
    }

}
