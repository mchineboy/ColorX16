%import textio
%import diskio
%import syslib
%import strings
%import conv

; User database module using REL (relative) file format
; Stores user records with random access capability

userdb {

    const ubyte REL_CHANNEL = 2
    const ubyte REL_DEVICE = 8
    const ubyte REL_SECONDARY = 0
    uword REL_FILENAME = "bbsusers"
    
    ; User record structure (fixed length for REL file)
    const ubyte RECORD_SIZE = 64  ; Fixed record size for REL file
    const ubyte USERNAME_MAX = 20
    const ubyte PASSWORD_HASH_SIZE = 16
    const ubyte SALT_SIZE = 8
    
    ; Record layout:
    ; Offset 0-19: Username (20 bytes, null-terminated)
    ; Offset 20-27: Salt (8 bytes)
    ; Offset 28-43: Password hash (16 bytes)
    ; Offset 44: User level (1 byte, 0-9)
    ; Offset 45: Flags (1 byte: bit 0=active, bit 1=verified, etc.)
    ; Offset 46-63: Reserved (18 bytes)
    
    ubyte @shared db_initialized = 0
    uword @shared max_records = 100  ; Maximum number of user records
    
    ; Initialize user database
    ; Creates REL file if it doesn't exist
    sub init() -> bool {
        diskio.drivenumber = REL_DEVICE
        
        ; Check if REL file exists
        if not diskio.exists(REL_FILENAME) {
            ; Create new REL file
            txt.print("Creating user database...")
            txt.nl()
            
            ; Open REL file for creation
            ; REL files use format: "filename,L,R" where L=record length, R=number of records
            uword rel_cmd = "bbsusers,L,"
            uword rec_size_str = conv.str_ub(RECORD_SIZE)
            uword max_rec_str = conv.str_uw(max_records)
            
            ; Build command: "bbsusers,L,64,R,100"
            uword cmd_buffer = "bbsusers,L,"  ; This would need proper string concatenation
            ; For now, use a simpler approach - create via OPEN with REL parameters
            
            ; Use CBM KERNAL to create REL file
            ; SETLFS: logical file, device, secondary
            cbm.SETLFS(REL_CHANNEL, REL_DEVICE, REL_SECONDARY)
            
            ; SETNAM: filename with REL parameters
            ; Format: "filename,L,record_length,R,max_records"
            ; REL files require this specific format
            uword rel_filename = "bbsusers,L,64,R,100"
            ubyte rel_filename_len = strings.length(rel_filename)
            cbm.SETNAM(rel_filename_len, rel_filename)
            
            ; OPEN the REL file
            cbm.OPEN()
            
            ubyte status = cbm.READST()
            if status != 0 {
                txt.print("Error creating REL file: ")
                txt.print_ub(status)
                txt.nl()
                return false
            }
            
            ; Close the file
            cbm.CLOSE(REL_CHANNEL)
            cbm.CLRCHN()
            
            txt.print("User database created successfully")
            txt.nl()
        }
        
        db_initialized = 1
        return true
    }
    
    ; Open REL file for reading/writing
    sub open_rel() -> bool {
        ; Open existing REL file
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
    ; Uses RECORD command: RECORD#channel, record_number
    sub seek_record(ubyte record_num) -> bool {
        ; Set output channel
        cbm.CHKOUT(REL_CHANNEL)
        
        ; Send RECORD command
        ; Format: RECORD#channel,record_number
        cbm.CHROUT($52)  ; 'R'
        cbm.CHROUT($23)  ; '#'
        cbm.CHROUT(REL_CHANNEL + $30)  ; Channel number as ASCII
        cbm.CHROUT($2c)  ; ','
        
        ; Send record number (convert to string)
        uword rec_str = conv.str_ub(record_num)
        uword i = 0
        while i < strings.length(rec_str) {
            cbm.CHROUT(@(rec_str + i))
            i++
        }
        
        cbm.CHROUT($0d)  ; Carriage return
        
        ; Check for error
        ubyte status = cbm.READST()
        cbm.CLRCHN()
        
        return status == 0
    }
    
    ; Read a user record from REL file
    sub read_record(ubyte record_num, uword buffer) -> bool {
        if not open_rel() {
            return false
        }
        
        ; Position to record
        if not seek_record(record_num) {
            close_rel()
            return false
        }
        
        ; Set input channel
        cbm.CHKIN(REL_CHANNEL)
        
        ; Read record data
        uword i = 0
        while i < RECORD_SIZE {
            ubyte ch = cbm.CHRIN()
            @(buffer + i) = ch
            i++
        }
        
        cbm.CLRCHN()
        close_rel()
        
        return true
    }
    
    ; Write a user record to REL file
    sub write_record(ubyte record_num, uword buffer) -> bool {
        if not open_rel() {
            return false
        }
        
        ; Position to record
        if not seek_record(record_num) {
            close_rel()
            return false
        }
        
        ; Set output channel
        cbm.CHKOUT(REL_CHANNEL)
        
        ; Write record data
        uword i = 0
        while i < RECORD_SIZE {
            cbm.CHROUT(@(buffer + i))
            i++
        }
        
        cbm.CLRCHN()
        close_rel()
        
        return true
    }
    
    ; Simple password hash (XOR-based, not cryptographically secure but functional)
    ; In production, should use proper hash algorithm
    sub hash_password(uword password, uword salt, uword hash_buffer) {
        ; Simple hash: XOR password bytes with salt, repeat
        ubyte pwd_len = strings.length(password)
        uword i = 0
        uword j = 0
        
        ; Initialize hash buffer
        while i < PASSWORD_HASH_SIZE {
            @(hash_buffer + i) = 0
            i++
        }
        
        ; Hash: XOR password with salt, cycling through
        i = 0
        while i < PASSWORD_HASH_SIZE {
            ubyte pwd_byte = 0
            if j < pwd_len {
                pwd_byte = @(password + j)
                j++
                if j >= pwd_len {
                    j = 0  ; Cycle through password
                }
            }
            
            ubyte salt_byte = @(salt + (i % SALT_SIZE))
            @(hash_buffer + i) = pwd_byte ^ salt_byte ^ (i as ubyte)
            i++
        }
    }
    
    ; Find a user record by username
    ; Returns record number if found, 255 if not found
    sub find_user(uword username) -> ubyte {
        ubyte[RECORD_SIZE] record_buffer
        ubyte i = 0
        
        while i < max_records {
            if read_record(i, &record_buffer) {
                ; Check if record is active (first byte != 0)
                if record_buffer[0] != 0 {
                    ; Compare username
                    bool match = true
                    uword j = 0
                    while j < USERNAME_MAX {
                        ubyte rec_char = record_buffer[j]
                        ubyte usr_char = @(username + j)
                        
                        if rec_char == 0 and usr_char == 0 {
                            break  ; Both ended, match
                        }
                        if rec_char != usr_char {
                            match = false
                            break
                        }
                        j++
                    }
                    
                    if match {
                        return i
                    }
                }
            }
            i++
        }
        
        return 255  ; Not found
    }
    
    ; Find first free record slot
    sub find_free_record() -> ubyte {
        ubyte[RECORD_SIZE] record_buffer
        ubyte i = 0
        
        while i < max_records {
            if read_record(i, &record_buffer) {
                ; Check if record is empty (first byte == 0)
                if record_buffer[0] == 0 {
                    return i
                }
            }
            i++
        }
        
        return 255  ; No free records
    }
    
    ; Add a new user
    sub add_user(uword username, uword password, ubyte user_level) -> bool {
        ; Check if user already exists
        if find_user(username) != 255 {
            return false  ; User already exists
        }
        
        ; Find free record
        ubyte record_num = find_free_record()
        if record_num == 255 {
            return false  ; No free records
        }
        
        ; Create record
        ubyte[RECORD_SIZE] record_buffer
        
        ; Clear record
        uword i = 0
        while i < RECORD_SIZE {
            record_buffer[i] = 0
            i++
        }
        
        ; Copy username
        ubyte username_len = strings.length(username)
        if username_len > USERNAME_MAX {
            username_len = USERNAME_MAX
        }
        i = 0
        while i < username_len {
            record_buffer[i] = @(username + i)
            i++
        }
        
        ; Generate salt (simple random - in production use better RNG)
        ubyte i2 = 0
        while i2 < SALT_SIZE {
            record_buffer[USERNAME_MAX + i2] = (i2 * 17 + username_len) as ubyte  ; Simple pseudo-random
            i2++
        }
        
        ; Hash password
        hash_password(password, &record_buffer[USERNAME_MAX], &record_buffer[USERNAME_MAX + SALT_SIZE])
        
        ; Set user level
        record_buffer[USERNAME_MAX + SALT_SIZE + PASSWORD_HASH_SIZE] = user_level
        
        ; Set flags (active, verified)
        record_buffer[USERNAME_MAX + SALT_SIZE + PASSWORD_HASH_SIZE + 1] = $03  ; Active + Verified
        
        ; Write record
        return write_record(record_num, &record_buffer)
    }
    
    ; Verify user password
    sub verify_password(uword username, uword password) -> bool {
        ubyte record_num = find_user(username)
        if record_num == 255 {
            return false  ; User not found
        }
        
        ; Read record
        ubyte[RECORD_SIZE] record_buffer
        if not read_record(record_num, &record_buffer) {
            return false
        }
        
        ; Check if active
        if (record_buffer[USERNAME_MAX + SALT_SIZE + PASSWORD_HASH_SIZE + 1] & $01) == 0 {
            return false  ; User not active
        }
        
        ; Hash provided password with stored salt
        ubyte[PASSWORD_HASH_SIZE] computed_hash
        hash_password(password, &record_buffer[USERNAME_MAX], &computed_hash)
        
        ; Compare hashes
        ubyte i3 = 0
        while i3 < PASSWORD_HASH_SIZE {
            if computed_hash[i3] != record_buffer[USERNAME_MAX + SALT_SIZE + i3] {
                return false
            }
            i3++
        }
        
        return true
    }
    
    ; Get user level
    sub get_user_level(uword username) -> ubyte {
        ubyte record_num = find_user(username)
        if record_num == 255 {
            return 0  ; Default level
        }
        
        ubyte[RECORD_SIZE] record_buffer
        if not read_record(record_num, &record_buffer) {
            return 0
        }
        
        return record_buffer[USERNAME_MAX + SALT_SIZE + PASSWORD_HASH_SIZE]
    }

}
