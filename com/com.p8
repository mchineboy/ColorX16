%import textio
%import syslib

; Communication module for BBS serial I/O
; Uses Device 2 for serial communication (as per C64/C128 convention)
; All functions use Prog8's built-in cbm module (no inline ASM)

com {

    const ubyte SERIAL_DEVICE = 2
    const ubyte SERIAL_CHANNEL = 1
    const ubyte SERIAL_SECONDARY = 0  ; Secondary address for serial device
    
    ubyte @shared device_initialized = 0
    ubyte @shared current_channel = 0

    ; Initialize serial communication device
    ; Opens Device 2 for communication
    sub init() -> bool {
        if device_initialized != 0 {
            return true  ; Already initialized
        }
        
        ; Set logical file parameters
        ; SETLFS: A=logical file number, X=device number, Y=secondary address
        cbm.SETLFS(SERIAL_CHANNEL, SERIAL_DEVICE, SERIAL_SECONDARY)
        
        ; Set filename (empty for device open)
        cbm.SETNAM(0, "")
        
        ; Open the device
        cbm.OPEN()
        
        ; Check for error
        ubyte status = cbm.READST()
        if status != 0 {
            txt.print("Error initializing serial device: ")
            txt.print_ub(status)
            txt.nl()
            return false
        }
        
        ; Set input channel
        cbm.CHKIN(SERIAL_CHANNEL)
        
        device_initialized = 1
        current_channel = SERIAL_CHANNEL
        
        return true
    }
    
    ; Close serial communication device
    sub close() {
        if device_initialized != 0 {
            cbm.CLRCHN()  ; Clear channels
            cbm.CLOSE(SERIAL_CHANNEL)  ; Close logical file
            device_initialized = 0
            current_channel = 0
        }
    }
    
    ; Read a character from serial device
    ; Returns: character byte, or 0 if no data available or error
    sub read_char() -> ubyte {
        if device_initialized == 0 {
            return 0
        }
        
        ; Check status first
        ubyte status = cbm.READST()
        if status != 0 {
            ; Check if it's just EOF (status bit 6 = $40)
            if (status & $40) == 0 {
                ; Real error, not just EOF
                return 0
            }
        }
        
        ; Read character
        ubyte ch = cbm.CHRIN()
        
        ; Check status after read
        status = cbm.READST()
        if status != 0 and (status & $40) == 0 {
            ; Error occurred
            return 0
        }
        
        return ch
    }
    
    ; Write a character to serial device
    sub write_char(ubyte ch) -> bool {
        if device_initialized == 0 {
            return false
        }
        
        ; Set output channel if not already set
        if current_channel != SERIAL_CHANNEL {
            cbm.CHKOUT(SERIAL_CHANNEL)
            current_channel = SERIAL_CHANNEL
        }
        
        ; Write character
        cbm.CHROUT(ch)
        
        ; Check for error
        ubyte status = cbm.READST()
        if status != 0 {
            return false
        }
        
        return true
    }
    
    ; Write a string to serial device
    sub write_str(uword str_ptr) -> bool {
        if device_initialized == 0 {
            return false
        }
        
        ; Set output channel if needed
        if current_channel != SERIAL_CHANNEL {
            cbm.CHKOUT(SERIAL_CHANNEL)
            current_channel = SERIAL_CHANNEL
        }
        
        ; Write string character by character
        uword i = 0
        while i < 255 {  ; Safety limit
            ubyte ch = @(str_ptr + i)
            if ch == 0 {
                break  ; End of string
            }
            
            cbm.CHROUT(ch)
            
            ; Check for error
            ubyte status = cbm.READST()
            if status != 0 {
                return false
            }
            
            i++
        }
        
        return true
    }
    
    ; Check if data is available to read
    ; Returns: true if data available, false otherwise
    sub data_available() -> bool {
        if device_initialized == 0 {
            return false
        }
        
        ; Check status
        ubyte status = cbm.READST()
        
        ; If status is 0, no error and potentially data available
        ; If status has EOF bit ($40) set, no more data
        if status == 0 {
            return true  ; No error, data might be available
        }
        
        if (status & $40) != 0 {
            return false  ; EOF reached
        }
        
        ; Other status might indicate error or no data
        return false
    }
    
    ; Get device status
    ; Returns: status byte from READST
    sub get_status() -> ubyte {
        if device_initialized == 0 {
            return 255  ; Error code for not initialized
        }
        
        return cbm.READST()
    }
    
    ; Flush input buffer (read and discard available characters)
    sub flush_input() {
        if device_initialized == 0 {
            return
        }
        
        ; Read and discard characters until no more available
        while data_available() {
            void read_char()
        }
    }

}