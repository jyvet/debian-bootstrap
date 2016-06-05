#!/bin/bash
################################################################################
#                           The MIT License (MIT)                              #
#                     Copyright (c) 2016 Jean-Yves VET                         #
#                                                                              #
# Permission is hereby granted, free of charge, to any person obtaining a copy #
# of this software and associated documentation files (the "Software"), to     #
# deal in the Software without restriction, including without limitation the   #
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or  #
# sell copies of the Software, and to permit persons to whom the Software is   #
# furnished to do so, subject to the following conditions:                     #
#                                                                              #
# The above copyright notice and this permission notice shall be included in   #
# all copies or substantial portions of the Software.                          #
#                                                                              #
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR   #
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,     #
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE  #
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER       #
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING      #
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS #
# IN THE SOFTWARE.                                                             #
#                                                                              #
####----[ INFORMATION ]-----------------------------------------------------####
#% Implementation:                                                             #
#-    version         0.1                                                      #
#-    url             https://github.com/jyvet/debian-bootstrap                #
#-    author          Jean-Yves VET <contact[at]jean-yves.vet>                 #
#-    copyright       Copyright (c) 2016                                       #
#-    license         MIT                                                      #
##################################HEADER_END####################################


####----[ PARAMETERS ]------------------------------------------------------####

    REPOSITORY='https://raw.githubusercontent.com/jyvet/debian-bootstrap/master'
    ROLE='bootstrap.yml'


####----[ GLOBAL VARIABLES ]------------------------------------------------####

    readonly SC_HSIZE=$(head -n99 "${0}" | grep -m1 -n "#HEADER_END#" |
                        cut -f1 -d:)     # Compute header size
    readonly SC_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" &&
                        pwd)             # Retrieve path where script is located
    readonly SC_NAME=$(basename ${0})    # Retrieve name of the script
    readonly SC_PID=$(echo $$)           # Retrieve PID of the script
    readonly VERSION=$(lsb_release -cs)  # Version of the current debian


####----[ ERRORS ]----------------------------------------------------------####

    # Generate error codes (emulate enum)
    ECODES=(OK ERROR ENROOT ENAN EINVOPT ECMD EINVNUM)
    for i in $(seq 0 $((${#ECODES[@]} -1 ))); do
        declare -r ${ECODES[$(($i))]}=$i;
    done

    # Register error messages
    ERRORS[$ENROOT]='not root, only processes own by user will be moved'
    ERRORS[$EINVOPT]='invalid option'
    ERRORS[$ENAN]='not a number'
    ERRORS[$ECMD]='$CMD not found. Please install the $PACKAGE package'
    ERRORS[$EINVNUM]='invalid number of arguments'


####----[ WARNINGS ]--------------------------------------------------------####

    # Register warning messages
    declare -A WARNINGS
    WARNINGS['not_root']='not root, only processes own by user will be moved'


####----[ GENERIC FUNCTIONS ]-----------------------------------------------####

    ############################################################################
    # Replace tags with content of variables.                                  #
    # Args:                                                                    #
    #      -$1: Input text.                                                    #
    #      -$2: Output variable where to store the resulting text.             #
    #      -$3: Start of the tag.                                              #
    #      -$4: End of the tag.                                                #
    # Result: store the resulting text in the variable defined by $2.          #
    tags_replace()
    {
        # Check number of input arguments
        if [[ "$#" -ne 4 ]]; then
            print_error $EINVNUM; return $?
        fi

        # Extract arguments
        local in="$1"
        local out="$2"
        local stag="$3"
        local etag="$4"

        # Search list of tags to replace
        local varList=$(echo "$in" | egrep -o "$stag[0-9A-Za-z_-]*$etag" |
                        sort -u | sed -e "s/^$stag//" -e "s/$etag$//")

        local res="$in"

        # Check if there are some tags to replace
        if [[ -n "$varList" ]]; then
            # Generate sed remplacement string
            sedOpts=''
            for var in $varList; do
                eval "value=\${${var}}"
                sedOpts="${sedOpts} -e 's#$stag${var}$etag#${value}#g'"
            done

            res=$(eval "echo -e \"\$in\" | sed $sedOpts")
        fi

        # Store resulting string in the output variable
        eval "$out=\"$res\""
    }

    ############################################################################
    # Remove all tags contained in a text.                                     #
    # Args:                                                                    #
    #      -$1: Input text.                                                    #
    #      -$2: Output variable where to store the resulting text.             #
    #      -$3: Start of the tag.                                              #
    #      -$4: End of the tag.                                                #
    # Result: store the resulting text in the variable defined by $2.          #
    tags_remove()
    {
        # Check number of input arguments
        if [[ "$#" -ne 4 ]]; then
            print_error $EINVNUM; return $?
        fi

        # Extract arguments
        local in="$1"
        local out="$2"
        local stag="$3"
        local etag="$4"

        # Remove tags
        local res="$(echo "$in" | sed -e "s#$stag[A-Za-z0-9_]*$etag##g")"

        # Store resulting string in the output variable
        eval "$out=\"$res\""
    }

    ############################################################################
    # Replace tags in a text with the content of variables.                    #
    # Args:                                                                    #
    #      -$1: Input text.                                                    #
    #      -$2: Output variable where to store the resulting text or output    #
    #           the content. ($2='var_name', $2='stdout' or $2='stderr')       #
    # Result: store or output the resulting text.                              #
    tags_replace_txt()
    {
        # Check number of input arguments
        if [[ "$#" -ne 2 ]]; then
            print_error $EINVNUM; return $?
        fi

        # Extract arguments
        local in="$1"
        local out="$2"

        # Replace all tags defined by {{TAG_NAME}}
        tags_replace "$in" "$out" '{{' '}}'

        # Check if the resulting string has to be printed in stderr or stdout
        case "$out" in
            stdout)
                eval "echo -e \"\$$out\""
                ;;
            stderr)
                eval "echo -e \"\$$out\"" 1>&2
                ;;
        esac
    }

    ############################################################################
    # Print text with colors if colors are enables.                            #
    # Args:                                                                    #
    #      -$1: Input text.                                                    #
    #      -$*: Other arguments for printf function.                           #
    # Result: print resulting string in stdout.                                #
    print_colors()
    {
        # Check number of input arguments
        if [[ "$#" -lt 1 ]]; then
            print_error $EINVNUM; return $?
        fi

        # Extract argument
        local in="$1<normal>"

        # Shift arguments
        shift

        # Check if colors are enabled and prepare output string
        if [[ "$ENABLE_COLORS" == "true" ]]; then
            # End tags
            local normal='$(tput sgr0)'
            local black="$normal"
            local red="$normal"
            local green="$normal"
            local grey1="$normal"
            local grey2="$normal"
            local grey3="$normal"
            local yellow="$normal"
            local blue="$normal"
            local magenta="$normal"
            local cyan="$normal"
            local white="$normal"
            local orange="$normal"
            local b="$normal"
            local i='$(tput ritm)'
            local u='$(tput rmul)'
            tags_replace "$in" 'OUT' '<\/' '>'

            # Start tags
            if [[ $(tput colors) -ge 256 ]] 2>/dev/null; then
                yellow='$(tput setaf 190)'
                orange='$(tput setaf 172)'
                grey1='$(tput setaf 240)'
                grey2='$(tput setaf 239)'
                grey3='$(tput setaf 238)'
            else
                yellow='$(tput setaf 3)'
                orange='$(tput setaf 3)'
                grey1='$(tput setaf 0)'
                grey2='$(tput setaf 0)'
                grey3='$(tput setaf 0)'
            fi

            black='$(tput setaf 0)'
            red='$(tput setaf 1)'
            green='$(tput setaf 2)'
            blue='$(tput setaf 4)'
            magenta='$(tput setaf 5)'
            cyan='$(tput setaf 6)'
            white='$(tput setaf 7)'
            b='$(tput bold)'
            i='$(tput sitm)'
            u='$(tput smul)'
            tags_replace "$OUT" 'OUT' '<' '>'
        else
            tags_remove "$in" 'OUT' '</' '>'
            tags_remove "$OUT" 'OUT' '<' '>'
        fi

        # Print string to stdout
        printf "$OUT" $*
    }

    ############################################################################
    # Print error in stderr.                                                   #
    # Args:                                                                    #
    #      -$1: Error code.                                                    #
    # Result: print error and return error code.                               #
    print_error()
    {
        # Extract argument
        local error_code="$1"

        # Check if output is not muted
        if [[ -z "$SILENT" ]]; then
            # Get error description
            eval "msg=\"${ERRORS[${error_code}]}\""

            # Print the error message
            print_colors '<red><b>Error:</b> </red>' 1>&2
            print_colors "<red>$msg</red>\n"         1>&2
        fi

        # Return the corresponding error code
        return "$error_code"
    }

    ############################################################################
    # Print warning in stderr.                                                 #
    # Args:                                                                    #
    #      -$1: Warning code.                                                  #
    # Result: print warning.                                                   #
    print_warning()
    {
        # Check if output is not muted
        if [[ -z "$SILENT" ]]; then
            # Extract argument
            local warning_code="$1"

            # Get warning description
            eval "msg=\"${WARNINGS[${warning_code}]}\""

            # Print the warning message
            print_colors '<orange><b>Warning:</b> </orange>' 1>&2
            print_colors "<orange>$msg</orange>\n"           1>&2
        fi
    }

    ############################################################################
    # Print info in stdout.                                                    #
    # Args:                                                                    #
    #      -$1: message to print.                                              #
    #      -$*: printf arguments.                                              #
    # Result: print info message.                                              #
    print_info()
    {
        # Check if output is not muted
        if [[ -z "$SILENT" ]]; then
            # Extract argument
            local msg="$1"

            # Shift arguments
            shift

            # Print the message
            print_colors '<yellow><b>Info:</b> </yellow>'
            print_colors "<yellow>$msg</yellow>\n" $*
        fi
    }

    ############################################################################
    # Print verbose info in stdout.                                            #
    # Args:                                                                    #
    #      -$1: verbosity (1, 2 or 3).                                         #
    #      -$2: message to print.                                              #
    #      -$*: printf arguments.                                              #
    # Result: print info in verbose mod.                                       #
    print_verbose()
    {
        # Check if output is not muted
        if [[ -z "$SILENT" ]]; then
            # Extract argument
            local level="$1"
            local msg="$2"

            # Shift arguments
            shift; shift

            # Check the verbosity level currently set
            if [[ "$VERBOSE_LEVEL" -ge "$level" ]]; then
                # Select color
                local color="white"
                case "$level" in
                    1)  color="grey1";;
                    2)  color="grey2";;
                    3)  color="grey3";;
                esac

                # Print the warning message
                print_colors "<$color><b>Verbose $level:</b> </$color>"
                print_colors "<$color>$msg</$color>\n" $*
            fi
        fi
    }

    ############################################################################
    # Print usage.                                                             #
    # Args:                                                                    #
    #       None                                                               #
    # Result: print short usage message.                                       #
    usage()
    {
        print_colors '<b>Usage:</b> '
        local tmp=$(head -n${SC_HSIZE:-99} "${0}" | grep -e "^#+" |
                   sed -e "s/^#+[ ]*//g" -e "s/#$//g")

        tags_replace_txt "$tmp" 'stdout'
    }

    ############################################################################
    # Print information related to development.                                #
    # Args:                                                                    #
    #       None                                                               #
    # Result: print version and contact information.                           #
    info()
    {
        local tmp=$(head -n${SC_HSIZE:-99} "${0}" | grep -e "^#-" |
                        sed -e "s/^#-//g" -e "s/#$//g" -e "s/\[at\]/@/g")

        tags_replace_txt "$tmp" 'stdout'
    }

    ############################################################################
    # Print full detailled usage.                                              #
    # Args:                                                                    #
    #       None                                                               #
    # Result: print help.                                                      #
    usage_full()
    {
        local tmp=$(head -n${SC_HSIZE:-99} "${0}" | grep -e "^#[%+]" |
                       sed -e "s/^#[%+-]//g" -e "s/#$//g")

        tags_replace_txt "$tmp" 'stdout'

        info
    }

    ############################################################################
    # Check if the current user is root.                                       #
    # Args:                                                                    #
    #       None                                                               #
    # Result: set global variable IS_ROOT.                                     #
    is_root()
    {
        if [[ 'root' != "$( whoami )" ]]; then
            IS_ROOT='false'
            print_error $ENROOT

            return "$?"
        else
            IS_ROOT='true'

            return "$OK"
        fi
    }

    ############################################################################
    # Check arguments.                                                         #
    # Args:                                                                    #
    #       All arguments provided.                                            #
    # Result: check if arguments are allowed and set global variables.         #
    check_arguments()
    {
        # Retireve verbosity arguments first
        local ttargs=''
        for arg in $*; do
            case "$arg" in
                -s)                SILENT='true';;
                --silent)          SILENT='true';;
                -v)                VERBOSE_LEVEL=1;;
                -vv)               VERBOSE_LEVEL=2;;
                -vvv)              VERBOSE_LEVEL=3;;
                *) ttargs="${ttargs} ${arg}";;
            esac
        done

        # Retireve color arguments
        local targs=''
        for arg in $ttargs; do
            case "$arg" in
                --colors)          enable_colors;;
                --disable-colors)  ENABLE_COLORS='false';;
                --enable-colors)   enable_colors;;
                *) targs="${targs} ${arg}";;
            esac
        done

        # Translate arguments to short options
        local args=''
        for arg in $targs; do
            local delim=''
            case $arg in
                --active)          args="${args}-a ";;
                --all)             args="${args}-a -k  "; enable_colors;;
                --coreset=*)       args="${args}-c $(echo "$arg" |
                                        sed 's/--.*=//g') ";;
                --exclude=*)       args="${args}-e $(echo "$arg" |
                                        sed 's/--.*=//g') ";;
                --help)            args="${args}-h ";;
                --kernel)          args="${args}-k ";;
                --refresh=*)       args="${args}-r $(echo "$arg" |
                                        sed 's/--.*=//g') ";;
                --version)         info; exit 0;;
                *) [[ "${arg:0:1}" == '-' ]] || delim="\""
                    args="${args}${delim}${arg}${delim} ";;
            esac
        done

        # Reset the positional parameters to the short options
        eval set -- $args

        # Available options
        local options='ac:e:hkr:'

        # Desactivate error handling by getops
        OPTERR=0

        # Parse arguments
        while getopts $options OPT; do
            case "$OPT" in
                a)  ENABLE_ACTIVE='true'
                    print_verbose 3 'enabling active mode';;
                c)  CORESET="$OPTARG"
                    print_verbose 3 'coreset defined to %s' "$CORESET";;
                e)  EXCLUDE="$EXCLUDE,$OPTARG"
                    print_verbose 3 'exclude list set to %s' "$EXCLUDE";;
                h)  usage_full; exit 0;;
                k)  ENABLE_KERNEL='true'
                    print_verbose 3 'enabling kernel processes migration';;
                r)  REFRESH="$OPTARG"
                    print_verbose 3 'refresh rate set to %ds' "$REFRESH";;
                \?) print_error $EINVOPT; usage; return $EINVOPT;;
            esac
        done
    }

    ############################################################################
    # Check if the tool is installed and the command is working on the system. #
    # Args:                                                                    #
    #       -$1: command to check.                                             #
    #       -$2: package name.                                                 #
    # Result: display an error and return error code ECMD if not installed.    #
    check_cmd()
    {
        # Check number of input arguments
        if [[ "$#" -ne 2 ]]; then
            print_error $EINVNUM; return $?
        fi

        # Extract parameters
        local cmd="$1"
        local package="$2"

        # Check if command works
        command -v $cmd >/dev/null 2>&1 ||
        {
            # Set variables for error message
            CMD=$cmd
            PACKAGE=$package

            # Print error message and return error code
            print_error $ECMD;
            return $?
        }

        print_verbose 3 "command %s available" "$cmd"

        return $OK
    }


####----[ FUNCTIONS ]-------------------------------------------------------####

    ############################################################################
    # Check if all dependencies are satisfied.                                 #
    # Args:                                                                    #
    #       None                                                               #
    # Result: return error code if one package is missing.                     #
    check_dependencies()
    {
        local res=$OK

        # Check taskset for processes migration
        check_cmd 'sudo' 'sudo' || res=$?

        return $res
    }

    ############################################################################
    # Configure source.list file.                                              #
    # Args:                                                                    #
    #       None                                                               #
    gen_source()
    {
        local path='/etc/apt/sources.list'
        local ftp='http://ftp.fr.debian.org/debian/'
        local httpsec='http://security.debian.org/'

        SRC="deb-src $httpsec {{VERSION}}/updates main contrib non-free"
        SRC="$SRC\ndeb $httpsec {{VERSION}}/updates main contrib non-free"
        SRC="$SRC\ndeb $ftp {{VERSION}} main contrib non-free"
        SRC="$SRC\ndeb-src $ftp {{VERSION}} main contrib non-free"
        SRC="$SRC\ndeb $ftp {{VERSION}}-updates main contrib non-free"
        SRC="$SRC\ndeb-src $ftp {{VERSION}}-updates main contrib non-free"

        tags_replace_txt "$SRC" "SRC"

        # Backup previous version
        cp $path $path.old

        # Update file
        echo -e "$SRC" > $path
    }


####----[ MAIN ]------------------------------------------------------------####

is_root || exit "-$?"

# Configure source.list
gen_source

# Update/upgrade packages
apt-get --force-yes --yes update
apt-get --force-yes --yes upgrade

# Install Ansible
apt-get --force-yes --yes install python-pip
pip install ansible

# Launch Ansible playbook
cd /tmp && wget "$REPOSITORY/$ROLE"
ansible-playbook -s $ROLE