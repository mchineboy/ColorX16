%import textio
%import config/config
%import conv

; Setup module for initial BBS configuration
; Runs when config file is not found

setup {

    sub run() {
        txt.print($93)  ; Clear screen
        txt.print("=== ColorX128 BBS Setup ===")
        txt.nl()
        txt.nl()
        txt.print("Welcome to the BBS setup wizard.")
        txt.nl()
        txt.print("This will help you configure your BBS.")
        txt.nl()
        txt.nl()
        
        ; Initialize config with defaults
        config.configpos = 0
        
        ; Get BBS name
        txt.print("BBS Name: ")
        uword bbs_name = txt.input_chars(40)
        if len(bbs_name) > 0 {
            config.setdirective("bbsname", bbs_name)
        } else {
            config.setdirective("bbsname", "ColorX128 BBS")
        }
        txt.nl()
        
        ; Get SysOp name
        txt.print("SysOp Name: ")
        uword sysop_name = txt.input_chars(40)
        if len(sysop_name) > 0 {
            config.setdirective("sysopname", sysop_name)
        } else {
            config.setdirective("sysopname", "SysOp")
        }
        txt.nl()
        
        ; Get drive number
        txt.print("Disk Drive Number (8-11): ")
        uword drive_input = txt.input_chars(2)
        ubyte drive_num = 8
        if len(drive_input) > 0 {
            ; Try to parse the number
            ubyte parsed = conv.str2ubyte(drive_input)
            if parsed >= 8 and parsed <= 11 {
                drive_num = parsed
            }
        }
        config.setdirective("drive", conv.str_ub(drive_num))
        config.configdrive = drive_num
        txt.nl()
        
        ; Get max users
        txt.print("Maximum Users: ")
        uword max_users_input = txt.input_chars(5)
        if len(max_users_input) > 0 {
            config.setdirective("maxusers", max_users_input)
        } else {
            config.setdirective("maxusers", "100")
        }
        txt.nl()
        
        ; Get time limit (minutes)
        txt.print("Time Limit (minutes, 0=unlimited): ")
        uword time_limit_input = txt.input_chars(5)
        if len(time_limit_input) > 0 {
            config.setdirective("timelimit", time_limit_input)
        } else {
            config.setdirective("timelimit", "60")
        }
        txt.nl()
        
        ; Get default user level
        txt.print("Default User Level (0-9): ")
        uword user_level_input = txt.input_chars(2)
        if len(user_level_input) > 0 {
            config.setdirective("defaultlevel", user_level_input)
        } else {
            config.setdirective("defaultlevel", "0")
        }
        txt.nl()
        
        txt.nl()
        txt.print("Setup complete!")
        txt.nl()
        txt.print("Saving configuration...")
        txt.nl()
        
        ; Save the config
        if config.save() {
            txt.print("Configuration saved successfully.")
            txt.nl()
            txt.nl()
            txt.print("Press any key to continue...")
            void txt.input_chars(1)
            return
        } else {
            txt.print("ERROR: Failed to save configuration!")
            txt.nl()
            txt.print("Press any key to exit...")
            void txt.input_chars(1)
            return
        }
    }

}
