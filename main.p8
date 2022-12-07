%zeropage kernalsafe
%include textio
%include config/config

main {
    sub start() {
        txt.print($0e)
        config.load()
        
    }
}

