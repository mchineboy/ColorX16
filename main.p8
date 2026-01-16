%zeropage kernalsafe
%import textio
%import config
%import setup
%import com
%import session
%import login
%import boards
%import messaging
%import files

main {
    sub start() {
        txt.cls()  ; Clear screen
        
        ; Try to load config
        if not config.load() {
            ; Config file not found or failed to load
            txt.nl()
            txt.print("=== Configuration Required ===")
            txt.nl()
            txt.nl()
            txt.print("No configuration file found.")
            txt.nl()
            txt.print("Entering setup mode...")
            txt.nl()
            txt.nl()
            sys.wait(60)  ; Wait 1 second
            
            ; Run setup
            setup.run()
            
            ; After setup, try loading config again
            if not config.load() {
                txt.print("FATAL: Could not load configuration after setup!")
                txt.nl()
                txt.print("Exiting...")
                txt.nl()
                return
            }
        }
        
        ; Config loaded successfully, continue with normal startup
        txt.print("BBS starting...")
        txt.nl()
        
        ; Initialize communication layer
        txt.print("Initializing serial communication...")
        txt.nl()
        if not com.init() {
            txt.print("ERROR: Failed to initialize serial communication!")
            txt.nl()
            txt.print("Exiting...")
            txt.nl()
            return
        }
        
        txt.print("Serial communication ready on Device 2")
        txt.nl()
        txt.nl()
        
        ; Initialize session system
        session.init()
        
        ; Initialize login system
        login.init()
        
        ; Initialize message boards
        boards.init()
        
        ; Initialize messaging system
        messaging.init()
        
        ; Main BBS event loop
        txt.print("BBS is now online and waiting for connections.")
        txt.nl()
        txt.print("Press STOP key to shutdown.")
        txt.nl()
        txt.nl()
        
        bool running = true
        while running {
            ; Wait for a connection
            if session.wait_for_connection() {
                ; Handle the session
                session.handle_session()
                
                ; Session ended, wait a moment before accepting next connection
                txt.print("Session ended. Waiting for next connection...")
                txt.nl()
                sys.wait(60)  ; 1 second delay
            } else {
                ; Timeout or error - check if we should continue
                txt.print("No connection received. Continue waiting? (Y/N)")
                txt.nl()
                ; For now, just continue waiting
                sys.wait(60)
            }
            
            ; Check for STOP key (this would need to be implemented)
            ; For now, run indefinitely until program is terminated
        }
        
        ; Cleanup on exit
        txt.print("Shutting down BBS...")
        txt.nl()
        session.init()  ; Reset session state
        com.close()
        txt.print("BBS shutdown complete.")
        txt.nl()
        
    }
}

