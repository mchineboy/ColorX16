%import cx16diskio
%import textio
%import floats

config {

    ubyte configdrive = 8
    uword configfilename = "bbsconfig"
    ubyte configbank = $0f
    str[] configdirectives = []
    str[] configvalues = []

    sub load() {
        txt.print("Loading...")

        uword status = cx16diskio.load(configdrive, configfilename, configbank)

        txt.print_uw(status)
        txt.nl()

        ubyte i = 0
        counter = 0
        cx16.rambank(configbank)
        configword = ""
        configpos = 0

        ; Read config file until we have a % at the start of a line
        while i != $25 {
            readchar = @($0000+counter)
            if readchar == $3d {
                configdirectives[configpos] = configword
                configword = ""
            } 
            else if readchar == $0d {
                configvalues[configpos] = configword
                configword = ""
                configpos = configpos + 1
            }
            else {
                configword = configword + chr(readchar)
            }
            i = readchar
        }

        return
    }

    sub getdirective(uword directive) {
        if directive in configdirectives {
            for i in 0 to len(configdirectives) {
                if configdirectives[i] == directive {
                    return configvalues[i]
                }
            }
            return configvalues[directive]
        }
        else {
            return ""
        }
    }

}