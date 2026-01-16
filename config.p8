%import textio
%import diskio
%import strings

config {

    ubyte configdrive = 8
    uword configfilename = "bbsconfig"
    ubyte configbank = 0      ; C128 uses banks 0-1, default to 0
    str[64] configdirectives
    str[64] configvalues
    uword configword = ""
    ubyte configpos = 0
    ubyte readchar = 0
    uword config_load_address = $1000  ; Memory address where config file is loaded

    sub load() -> bool {
        txt.print("Loading config...")
        txt.nl()

        ; Set the drive number for diskio
        diskio.drivenumber = configdrive

        ; Check if config file exists first
        if not diskio.exists(configfilename) {
            txt.print("Config file not found.")
            txt.nl()
            return false
        }

        ; Load the config file into memory
        ; diskio.load() with address_override loads at specified address (skips 2-byte header)
        ; Returns end address+1 on success, or 0 on error
        uword end_address = diskio.load(configfilename, config_load_address)
        
        if end_address == 0 {
            txt.print("Error: Could not load config file")
            txt.nl()
            return false
        }

        uword file_size = end_address - config_load_address
        txt.print("Loaded: ")
        txt.print_uw(file_size)
        txt.print(" bytes")
        txt.nl()

        ; Initialize parsing variables
        configword = ""
        configpos = 0
        ubyte i = 0
        uword counter = 0

        ; Read config file until we have a % at the start of a line
        ; Config format: "directive=value" lines, ends with % character ($25)
        ; diskio.load() with address_override skips the 2-byte header, so we start at config_load_address
        uword parse_start = config_load_address

        while i != $25 {  ; $25 is '%' character
            readchar = @(parse_start + counter)
            
            if readchar == $3d {  ; '=' character
                configdirectives[configpos] = configword
                configword = ""
            } 
            else if readchar == $0d {  ; Carriage return
                configvalues[configpos] = configword
                configword = ""
                configpos = configpos + 1
            }
            else if readchar != $0a {  ; Skip line feed, but process other chars
                ; Convert byte to character string
                ubyte[2] char_buf
                char_buf[0] = readchar
                char_buf[1] = 0
                configword = configword + &char_buf
            }
            
            i = readchar
            counter = counter + 1
            
            ; Safety check to prevent infinite loop
            if counter > 16384 {
                txt.print("Error: Config file too large or malformed")
                txt.nl()
                break
            }
        }

        txt.print("Config loaded: ")
        txt.print_ub(configpos)
        txt.print(" entries")
        txt.nl()

        return true
    }
    
    ; Save config to disk
    ; Creates a simple text file with "directive=value" lines, ending with %
    sub save() -> bool {
        txt.print("Saving config...")
        txt.nl()
        
        ; Set the drive number for diskio
        diskio.drivenumber = configdrive
        
        ; Open file for writing
        if not diskio.f_open_w(configfilename) {
            txt.print("Error: Could not open config file for writing")
            txt.nl()
            return false
        }
        
        ; Write each directive=value pair
        ubyte i = 0
        while i < configpos {
            ; Write directive
            uword dir_len = strings.length(configdirectives[i])
            if dir_len > 0 {
                if not diskio.f_write(configdirectives[i], dir_len) {
                    diskio.f_close_w()
                    return false
                }
            }
            
            ; Write =
            ubyte eq = $3d
            if not diskio.f_write(&eq, 1) {
                diskio.f_close_w()
                return false
            }
            
            ; Write value
            uword val_len = strings.length(configvalues[i])
            if val_len > 0 {
                if not diskio.f_write(configvalues[i], val_len) {
                    diskio.f_close_w()
                    return false
                }
            }
            
            ; Write carriage return
            ubyte cr = $0d
            if not diskio.f_write(&cr, 1) {
                diskio.f_close_w()
                return false
            }
            i++
        }
        
        ; Write terminator %
        ubyte term = $25
        if not diskio.f_write(&term, 1) {
            diskio.f_close_w()
            return false
        }
        
        ; Close file
        diskio.f_close_w()
        
        txt.print("Config saved successfully")
        txt.nl()
        return true
    }
    
    ; Set a config directive value (adds or updates)
    sub setdirective(uword directive, uword value) {
        ; Check if directive already exists
        ubyte i = 0
        while i < 64 {
            if configdirectives[i] == directive {
                configvalues[i] = value
                return
            }
            i++
        }
        ; Add new directive
        configdirectives[configpos] = directive
        configvalues[configpos] = value
        configpos = configpos + 1
    }

    sub getdirective(uword directive) -> uword {
        ubyte i = 0
        while i < 64 {
            if configdirectives[i] == directive {
                return configvalues[i]
            }
            i++
        }
        return ""
    }

}