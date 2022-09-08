#!/bin/zsh

#
#  DEPNotify Onboarder
#  Copyright 2022 Konica Minolta Business Solutions U.S.A., Inc.
#
#  Based on DEPNotifyStarter, Copyright 2018 Jamf Professional Services
#
#  ## LICENSE
#
#  Permission is hereby granted, free of charge, to any person obtaining a copy of this
#  software and associated documentation files (the "Software"), to deal in the Software
#  without restriction, including without limitation the rights to use, copy, modify, merge,
#  publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
#  to whom the Software is furnished to do so, subject to the following conditions:
#
#  The above copyright notice and this permission notice shall be included in all copies or
#  substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
#  INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
#  PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
#  FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
#  OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
#  DEALINGS IN THE SOFTWARE.
#

# TODO: Support validation and re-entering the registration screen. This will be implemented with a Jamf Policy. The policy could fail or the registration information removed to retry.
# TODO: Add support for adding resources.

#  -----------------------------------------------------------------------------

# 
#  Display a debug description of a list of variables.
#
#  Usage:
#  debugDescription "title" "var 1" ["var n"...] 
#
debugDescription() {
    local -r title="$1"
    printf "\n## %s ##\n" "$title"
    for var in "${@:2}" ; do
        printf "%-30s = %s\n\n" "$var" "${(P)var}"
    done
}

#  -----------------------------------------------------------------------------
#  - Global Static Variables
#  -----------------------------------------------------------------------------

declare -r DEPNotifyApp="/Applications/Utilities/DEPNotify.app"
declare -r DEPNotifyLog="/var/tmp/depnotify.log"
declare -r DEPNotifyOldLog="/var/tmp/depnotify_old.log"
declare -r DEPNotifyDebugLog="/var/tmp/depnotifyDebug.log"
declare -r DEPNotifyDoneFile="/var/tmp/com.depnotify.provisioning.done"
declare -r DEPNotifyRegisterDoneFile="/var/tmp/com.depnotify.registration.done"
declare -r DEPNotifyOnboarderDoneFile="/private/var/db/.DEPNotifyOnboarderSetupDone"
declare -r DEPNotifyOnboarderLaunchDaemon="/Library/LaunchDaemons/us.konicaminolta.DEPNotifyOnboarder.plist"
declare -r configurationPlist="/Library/Managed Preferences/menu.nomad.DEPNotify"

debugDescription "File Paths" DEPNotifyApp DEPNotifyLog DEPNotifyOldLog DEPNotifyDebugLog \
    DEPNotifyDoneFile DEPNotifyRegisterDoneFile configurationPlist DEPNotifyOnboarderDoneFile \
    DEPNotifyOnboarderLaunchDaemon

#  -----------------------------------------------------------------------------
#  - Functions
#  -----------------------------------------------------------------------------

#
#  Log a message.
#
#  Usage: 
#  debugLog "message"
#
debugLog() { 
    local -r logDate="$(date "+%a %h %d %H:%M:%S")"
    echo "$logDate:" "$@" >> "$DEPNotifyDebugLog" 
    >&2 echo "$logDate:" "$@" # TODO: throttle dups **********
}

#
#  Print a fatal error message to stderr then exit.
#
#  Usage: 
#  fatalError "message"
#
fatalError() { 
    debugLog "Error:" "$@"
    exit 1
}

# 
#  Convert an integer value of "1" or "0" to "true" or "false".
#
#  Usage:
#  value="$(boolFromInt "integer value")"
#
boolFromInt() {
    local -i -r intValue="$1" # The integer to convert to a boolean string
    case "$intValue" in
        0) echo false ;;
        1) echo true ;;
        *) fatalError "Invalid boolean value '$intValue'." ;;
    esac
}

# 
#  Read a value from the "menu.nomad.DEPNotify" plist domain. These settings must be managed.
#
#  Usage:
#  value="$(valueForKey "key" [-defaultValue "default value"])"
#
valueForKey() {
    local -r key="$1"          # The key for a value to look up in the plist
    local -r defaultLabel="$2" # Use `-defaultValue` to specify a default value
    local -r defaultValue="$3" # An optional default value
    local value
    if value="$(/usr/bin/defaults read "$configurationPlist" "$key" 2> /dev/null)" ; then
        if [ "Type is boolean" = "$(/usr/bin/defaults read-type "$configurationPlist" "$key" 2> /dev/null)" ] ; then
            value="$(boolFromInt "$value")"
        fi
        echo "$value"
    elif [ "$defaultLabel" = "-defaultValue" ] ; then
        echo "$defaultValue"
    else 
        fatalError "Missing value for key '$key'."
    fi
}

# 
#  Read an array from the "menu.nomad.DEPNotify" plist domain. These settings must be managed.
#
#  Usage:
#  value="$(valueForKey "key")"
#
arrayForKey() {
    local -r key="$1" # The key for a value to look up in the plist
    if [ "Type is array" = "$(/usr/bin/defaults read-type "$configurationPlist" "$key" 2> /dev/null)" ] ; then
        local -r list="$(valueForKey "$key" -defaultValue "")"
        echo "$list" | sed -e 's/    "//g' -e 's/",//g' -e 's/^[()]$//g' -e 's/"//g'
    fi
}

# 
#  Lookup the PID for a process. If multiple instances are running, the PID for the first process is returned.
#
#  Usage:
#  lookupPID "process"
#
lookupPID() {
    local -r processName="$1"
    /usr/bin/pgrep -l "$processName" | /usr/bin/cut -d " " -f1 2> /dev/null
}

# 
#  Stop a process.
#
#  Usage:
#  stopProcess "process"
#
stopProcess() {
    local -r processName="$1"
    local pid
    pid="$(lookupPID "$processName")"
    until [ "$pid" = "" ]; do
        debugLog "Stopping the previously-opened instance of $processName (PID $pid)."
        kill "$pid"
        pid="$(lookupPID "$processName")"
    done
}

# 
#  Wait for a process to complete before continuing.
#
#  Usage:
#  waitForProcessToComplete "process" -progressMessage "message"
#
waitForProcessToComplete() {
    local -r processName="$1"
    local -r message="$3"
    local pid
    pid="$(lookupPID "$processName")"
    until [ "$pid" = "" ]; do
        debugLog "$message (PID $pid)" 
        /bin/sleep 1
        pid="$(lookupPID "$processName")"
    done
}

# 
#  Wait for a process to start before continuing.
#
#  Usage:
#  waitForProcessToStart "process" -progressMessage "message"
#
waitForProcessToStart() {
    local -r processName="$1"
    local -r message="$3"
    local pid 
    pid="$(lookupPID "$processName")"
    until [ "$pid" != "" ]; do
        debugLog "$message (PID $pid)" 
        /bin/sleep 1
        pid="$(lookupPID "$processName")"
    done
}

# 
#  Send a command to DEPNotify.
#
#  Usage:
#  logCommand "command" ["message"]
#
logCommand() {
    local -r commandName="$1"
    local -r message="$2"
    echo "Command: $commandName: $message" >> "$DEPNotifyLog"
    if [ "$testingMode" = true ]; then
        debugLog "Command: $commandName: $message"
    fi
}

# 
#  Update DEPNotify status message.
#
#  Usage:
#  logStatus "message"
#
logStatus() {
    local -r message="$1"
    echo "Status: $message" >> "$DEPNotifyLog"
    if [ "$testingMode" = true ]; then
        debugLog "Status: $message"
    fi
}

# 
#  Deploy a file from a base64 encoded string.
#
#  Usage:
#  deployDataFile "file path" "base64 data"
#
deployDataFile() {
    local -r file="$1"
    local -r data="$2"
    if [ "$file" != "" ] ; then
        debugLog "Writing base64 data to file: $file"
        echo "$data" | /usr/bin/base64 -d 2> /dev/null > "$file" 
        /usr/sbin/chown root:wheel "$file"
        /bin/chmod 644 "$file"
    fi
}

# 
#  Deploy a file from a text string.
#
#  Usage:
#  deployTextFile "file path" "text data"
#
deployTextFile() {
    local -r file="$1"
    local -r text="$2"
    if [ "$file" != "" ] ; then
        debugLog "Writing text data to file: $file"
        echo "$text" > "$file" 
        /usr/sbin/chown root:wheel "$file"
        /bin/chmod 644 "$file"
    fi
}

#  -----------------------------------------------------------------------------
#  - Beginning of Script
#  -----------------------------------------------------------------------------

# Ensure the script was executed with root priviledges.
declare -r runAsUser="$(whoami)"
if [ "$runAsUser" != root ] && [ "$runAsUser" != _mbsetupuser ] ; then
    fatalError "DEPNotify Onboarder must executed with root priviledges."
fi

#  -----------------------------------------------------------------------------
#  - Configuration
#  -----------------------------------------------------------------------------

# Read configuration values from the "menu.nomad.DEPNotify" plist domain.

# General Configuration
declare -r testingMode="$(valueForKey testingMode -defaultValue false)"
declare -r DEPNotifyUserInputPlist="$(valueForKey pathToPlistFile)" # DEPNotify key
declare -r noSleep="$(valueForKey noSleep -defaultValue false)"
declare -r selfDestruct="$(valueForKey selfDestruct -defaultValue false)"

debugDescription "General Configuration" testingMode DEPNotifyUserInputPlist noSleep selfDestruct

# General Appearance Configuration
declare -r fullscreen="$(valueForKey fullscreen -defaultValue true)"
declare bannerImagePath="$(valueForKey bannerImagePath -defaultValue "/Applications/Self Service.app/Contents/Resources/AppIcon.icns")"
declare -r orgName="$(valueForKey orgName -defaultValue "Organization")"
declare -r bannerTitle="$(valueForKey bannerTitle -defaultValue "Welcome to $orgName")"
declare -r supportContactDetails="$(valueForKey supportContactDetails -defaultValue "email helpdesk@company.com")"
declare -r mainText="$(valueForKey mainText -defaultValue 'Thanks for choosing a Mac at '"$orgName"'! We want you to have a few applications and settings configured before you get started with your new Mac. This process should take 10 to 20 minutes to complete. \n \n If you need additional software or help, please visit the Self Service app in your Applications folder or on your Dock.')"
declare -r installStartStatus="$(valueForKey installStartStatus -defaultValue "Initial Configuration Starting...")"
declare -r installCompleteText="$(valueForKey installCompleteText -defaultValue "Configuration Complete!")"
declare -r completeMethodDropdownAlert="$(valueForKey completeMethodDropdownAlert -defaultValue false)"
declare -r completeAlertText="$(valueForKey completeAlertText -defaultValue "Your Mac is now finished with initial setup and configuration. Press Quit to get started!")"
declare -r completeMainText="$(valueForKey completeMainText -defaultValue 'Your Mac is now finished with initial setup and configuration.')"
declare -r completeButtonText="$(valueForKey completeButtonText -defaultValue "Get Started!")"
declare -r statusTextAlignment="$(valueForKey statusTextAlignment -defaultValue "")" # DEPNotify key

debugDescription "General Appearance" fullscreen bannerImagePath orgName bannerTitle \
    supportContactDetails mainText installStartStatus installCompleteText completeMethodDropdownAlert \
    completeAlertText completeMainText completeButtonText statusTextAlignment

# Self Service Configuration
declare -r selfServiceCustomBranding="$(valueForKey selfServiceCustomBranding -defaultValue false)"
declare -r selfServiceAppName="$(valueForKey selfServiceAppName -defaultValue "Self Service.app")"
declare -r selfServiceCustomWait="$(valueForKey selfServiceCustomWait -defaultValue 20)"

debugDescription "Self Service" selfServiceCustomBranding selfServiceAppName selfServiceCustomWait

# Error Screen Configuration
declare -r errorBannerTitle="$(valueForKey errorBannerTitle -defaultValue "Uh oh, Something Needs Fixing!")"
declare errorMainText="$(valueForKey errorMainText -defaultValue 'We are sorry that you are experiencing this inconvenience with your new Mac. However, we have the nerds to get you back up and running in no time! \n \n Please contact IT right away and we will take a look at your computer ASAP. \n \n')"
errorMainText="$errorMainText $supportContactDetails"
declare -r errorStatus="$(valueForKey errorBannerTitle -defaultValue "Setup Failed")"

debugDescription "Error Screen" errorBannerTitle errorMainText errorStatus

# FileVault Configuration
declare -r FVAlertText="$(valueForKey FVAlertText -defaultValue "Your Mac must logout to start the encryption process. You will be asked to enter your password and click OK or Continue a few times. Your Mac will be usable while encryption takes place.")"
declare -r FVCompleteMainText="$(valueForKey FVCompleteMainText -defaultValue 'Your Mac must logout to start the encryption process. You will be asked to enter your password and click OK or Continue a few times. Your Mac will be usable while encryption takes place.')"
declare -r FVCompleteButtonText="$(valueForKey FVCompleteButtonText -defaultValue "Logout")"

debugDescription "FileVault" fvAlertText fvCompleteMainText fvCompleteButtonText

# EULA Configuration
declare -r EULAEnabled="$(valueForKey EULAEnabled -defaultValue false)" # Enables EULA acceptance check
declare -r EULAStatus="$(valueForKey EULAStatus -defaultValue "Waiting on completion of EULA acceptance")"
declare -r EULAButton="$(valueForKey EULAButton -defaultValue "Read and Agree to EULA")"
declare -r EULAMainTitle="$(valueForKey EULAMainTitle -defaultValue "")" # "Organization End User License Agreement"
declare -r EULASubTitle="$(valueForKey EULASubTitle -defaultValue "")" # "Please agree to the following terms and conditions to start configuration of this Mac"
declare -r pathToEULA="$(valueForKey pathToEULA -defaultValue "")" # "/Users/Shared/eula.txt"

debugDescription "EULA" EULAEnabled EULAStatus EULAButton EULAMainTitle EULASubTitle pathToEULA

# Registration Configuration
declare -r registrationEnabled="$(valueForKey registrationEnabled -defaultValue false)" # Enables registration check
declare -r registrationTitle="$(valueForKey registrationTitle -defaultValue "Register Mac at $orgName")"
declare -r registrationStatus="$(valueForKey registrationStatus -defaultValue "Waiting on completion of computer registration")"
declare -r registrationButton="$(valueForKey registrationButton -defaultValue "Register Your Mac")"
declare -r registrationBeginWord="$(valueForKey registrationBeginWord -defaultValue "Setting")"
declare -r registrationMiddleWord="$(valueForKey registrationMiddleWord -defaultValue "to")"

declare -r registrationMainTitle="$(valueForKey registrationMainTitle -defaultValue "")"
declare -r registrationButtonLabel="$(valueForKey registrationButtonLabel -defaultValue "")"
declare -r registrationPicturePath="$(valueForKey registrationPicturePath -defaultValue "")"

declare -r textField1Label="$(valueForKey textField1Label -defaultValue "")"
declare -r textField1CustomTrigger="$(valueForKey textField1CustomTrigger -defaultValue "")"

declare -r textField2Label="$(valueForKey textField2Label -defaultValue "")"
declare -r textField2CustomTrigger="$(valueForKey textField2CustomTrigger -defaultValue "")"

declare -r popupButton1Label="$(valueForKey popupButton1Label -defaultValue "")"
declare -r popupButton1CustomTrigger="$(valueForKey popupButton1CustomTrigger -defaultValue "")"

declare -r popupButton2Label="$(valueForKey popupButton2Label -defaultValue "")"
declare -r popupButton2CustomTrigger="$(valueForKey popupButton2CustomTrigger -defaultValue "")"

declare -r popupButton3Label="$(valueForKey popupButton3Label -defaultValue "")"
declare -r popupButton3CustomTrigger="$(valueForKey popupButton3CustomTrigger -defaultValue "")"

declare -r popupButton4Label="$(valueForKey popupButton4Label -defaultValue "")"
declare -r popupButton4CustomTrigger="$(valueForKey popupButton4CustomTrigger -defaultValue "")"

debugDescription "Registration" registrationEnabled registrationTitle \
    registrationStatus registrationButton registrationBeginWord registrationMiddleWord \
    registrationMainTitle registrationButtonLabel registrationPicturePath \
    textField1Label textField1CustomTrigger \
    textField2Label textField2CustomTrigger \
    popupButton1Label popupButton1CustomTrigger \
    popupButton2Label popupButton2CustomTrigger \
    popupButton3Label popupButton3CustomTrigger \
    popupButton4Label popupButton4CustomTrigger

# Policy List Configuration
IFS=$'\n'
declare -a -r policies=($(arrayForKey policies))
unset IFS
declare -r inventoryCustomTrigger="$(valueForKey inventoryCustomTrigger -defaultValue "inventoryUpdate")"

debugDescription "Policy List" policies inventoryCustomTrigger

# Deploy Files Configuration
declare -r deployDataFile1Path="$(valueForKey deployDataFile1Path -defaultValue "")"
declare -r deployDataFile2Path="$(valueForKey deployDataFile2Path -defaultValue "")"
declare -r deployDataFile3Path="$(valueForKey deployDataFile3Path -defaultValue "")"
declare -r deployDataFile4Path="$(valueForKey deployDataFile4Path -defaultValue "")"
declare -r deployDataFile5Path="$(valueForKey deployDataFile5Path -defaultValue "")"
declare -r deployDataFile6Path="$(valueForKey deployDataFile6Path -defaultValue "")"

declare -r deployTextFile1Path="$(valueForKey deployTextFile1Path -defaultValue "")"
declare -r deployTextFile2Path="$(valueForKey deployTextFile2Path -defaultValue "")"
declare -r deployTextFile3Path="$(valueForKey deployTextFile3Path -defaultValue "")"
declare -r deployTextFile4Path="$(valueForKey deployTextFile4Path -defaultValue "")"
declare -r deployTextFile5Path="$(valueForKey deployTextFile5Path -defaultValue "")"
declare -r deployTextFile6Path="$(valueForKey deployTextFile6Path -defaultValue "")"

debugDescription "Deploy Files" \
    deployDataFile1Path deployDataFile2Path deployDataFile3Path \
    deployDataFile4Path deployDataFile5Path deployDataFile6Path \
    deployTextFile1Path deployTextFile2Path deployTextFile3Path \
    deployTextFile4Path deployTextFile5Path deployTextFile6Path 

# Check if onboarding already marked as complete.
if [ -f "$DEPNotifyOnboarderDoneFile" ]; then
    if [ "$testingMode" = true ]; then
        debugLog "'testingMode' enabled. Allowing DEPNotify Onboarder to run again."
        /bin/rm "$DEPNotifyOnboarderDoneFile"
    else
        echo "Onboarding not required."
        exit 0
    fi
fi

# DEPNotify will run after Apple Setup Assistant
waitForProcessToComplete "Setup Assistant" -progressMessage "Setup Assistant Still Running."

# Deploy Files
declare -i i=0
for i in {1..6} ; do
    declare dataProperty="deployDataFile${i}Path"
    deployDataFile "${(P)dataProperty}" "$(valueForKey "deployDataFile${i}Data" -defaultValue "")"
    declare textProperty="deployDataFile${i}Path"
    deployTextFile "${(P)textProperty}" "$(valueForKey "deployTextFile${i}Data" -defaultValue "")"
done

# Checking to see if the Finder is running now before continuing. This can help
# in scenarios where an end user is not configuring the device.
waitForProcessToStart "Finder" -progressMessage "Finder process not found. Assuming device is at login screen."

# After the Apple Setup completed. Now safe to grab the current user and user ID
declare -r currentUser="$(/usr/bin/stat -f "%Su" /dev/console)"
declare -i -r currentUID="$(/usr/bin/id -u "$currentUser")"
debugLog "Current user set to $currentUser (id: $currentUID)."

# Stop DEPNotify if there was already a DEPNotify window running (from a PreStage package postinstall script).
stopProcess "DEPNotify"

# Stop BigHonkingText if it's running (from a PreStage package postinstall script).
stopProcess "BigHonkingText"

# Adding Check and Warning if Testing Mode is off and BOM files exist
if [[ ( -f "$DEPNotifyLog" || -f "$DEPNotifyDoneFile" ) && "$testingMode" = false ]] ; then
    debugLog "'testingMode' set to false but config files were found in /var/tmp. Letting user know and exiting."
    mv "$DEPNotifyLog" "$DEPNotifyOldLog"
    logCommand MainTitle "$errorBannerTitle"
    logCommand MainText "$errorMainText"
    logStatus "$errorStatus"
    /bin/launchctl asuser $currentUID /usr/bin/open -a "$DEPNotifyApp" --args -path "$DEPNotifyLog"
    /bin/sleep 5
    exit 1
fi

# If 'selfServiceCustomBranding' is set to true. Loading the updated icon
if [ "$selfServiceCustomBranding" = true ] ; then
    /usr/bin/open -a "/Applications/$selfServiceAppName" --hide

    # Loop waiting on the branding image to properly show in the users library
    declare -i selfServiceCounter=0
	declare customBrandingPNG="/Users/$currentUser/Library/Application Support/com.jamfsoftware.selfservice.mac/Documents/Images/brandingimage.png"
	until [ -f "$customBrandingPNG" ] ; do
		logToFile -debug "Waiting for branding image from Jamf Pro."
		/bin/sleep 1
		(( selfServiceCounter++ ))
		if [ "$selfServiceCounter" -gt "$selfServiceCustomWait" ] ; then
		   customBrandingPNG="/Applications/Self Service.app/Contents/Resources/AppIcon.icns"
		   break
		fi
	done

    # Setting Banner Image for DEP Notify to Self Service Custom Branding
    bannerImagePath="$customBrandingPNG"

    # Closing Self Service
    selfServicePID="$(lookupPID "Self Service")"
    debugLog "Self Service custom branding icon has been loaded. Killing Self Service PID $selfServicePID."
    kill "$selfServicePID"
elif [ ! -f "$bannerImagePath" ] ; then
    bannerImagePath="/Applications/Self Service.app/Contents/Resources/AppIcon.icns"
fi

# Setting custom image if specified
if [ "$bannerImagePath" != "" ] ; then logCommand Image "$bannerImagePath" ; fi

# Setting custom title if specified
if [ "$bannerTitle" != "" ] ; then logCommand MainTitle "$bannerTitle" ; fi

# Setting custom main text if specified
if [ "$mainText" != "" ] ; then logCommand MainText "$mainText" ; fi

# EULA Configuration
if [ "$EULAEnabled" = true ]; then
    # If testing mode is on, this will remove EULA specific configuration files
    if [ "$testingMode" = true ] && [ -f "$DEPNotifyUserInputPlist" ] ; then rm "$DEPNotifyUserInputPlist" ; fi

    # TODO: Write out EULA file ******************

    if [ "$pathToEULA" = "" ] ; then fatalError "No EULA file specified." ; fi
    if [ ! -e "$pathToEULA" ] ; then fatalError "Unable to find '$pathToEULA'." ; fi

    # Setting ownership of EULA file
    /usr/sbin/chown "${currentUser}:staff" "$pathToEULA"
    /bin/chmod 444 "$pathToEULA"
fi

# Registration Configuration
if [ "$registrationEnabled" = true ] ; then
    # If testing mode is on, this will remove registration specific configuration files
    if [ "$testingMode" = true ] && [ -f "$DEPNotifyRegisterDoneFile" ] ; then rm "$DEPNotifyRegisterDoneFile" ; fi
fi

# Opening the app after initial configuration
if [ ! -d "$DEPNotifyApp" ] ; then
    fatalError "Unable to find '$DEPNotifyApp'."
fi
if [ "$fullscreen" = true ] ; then
    /bin/launchctl asuser "$currentUID" /usr/bin/open -a "$DEPNotifyApp" --args -path "$DEPNotifyLog" -fullScreen
else
    /bin/launchctl asuser "$currentUID" /usr/bin/open -a "$DEPNotifyApp" --args -path "$DEPNotifyLog"
fi

# Grabbing the DEP Notify Process ID for use later
DEPNotifyPID="$(lookupPID "DEPNotify")"
until [ "$DEPNotifyPID" != "" ] ; do
    debugLog "Waiting for DEPNotify to start to gather the process ID."
    /bin/sleep 1
    DEPNotifyPID="$(lookupPID "DEPNotify")"
done

# Using Caffeinate binary to keep the computer awake if enabled
if [ "$noSleep" = true ] ; then
    debugLog "Caffeinating DEPNotify process. Process ID: $DEPNotifyPID"
    /usr/bin/caffeinate -disu -w "$DEPNotifyPID" &
fi

# Adding an alert prompt to let admins know that the script is in testing mode
if [ "$testingMode" = true ] ; then
    logCommand Alert "DEPNotify is in testing mode. Script will not run Policies or other commands that make changes to this computer."
fi

# Adding nice text and a brief pause for prettiness
logStatus "installStartStatus"
/bin/sleep 5

# Counter is for making the determinate look nice. Starts at one and adds more based on EULA, register, or other options.
declare additionalOptionsCounter=1
if [ "$EULAEnabled" = true ]          ; then (( additionalOptionsCounter++ )) ; fi
if [ "$registrationEnabled" = true ]  ; then (( additionalOptionsCounter++ ))
    if [ "$textField1Label" != "" ]   ; then (( additionalOptionsCounter++ )) ; fi
    if [ "$textField2Label" != "" ]   ; then (( additionalOptionsCounter++ )) ; fi
    if [ "$popupButton1Label" != "" ] ; then (( additionalOptionsCounter++ )) ; fi
    if [ "$popupButton2Label" != "" ] ; then (( additionalOptionsCounter++ )) ; fi
    if [ "$popupButton3Label" != "" ] ; then (( additionalOptionsCounter++ )) ; fi
    if [ "$popupButton4Label" != "" ] ; then (( additionalOptionsCounter++ )) ; fi
fi

# Checking policy array and adding the count from the additional options above.
declare -r arrayLength="$(( ${#policies[@]} + additionalOptionsCounter ))"
logCommand Determinate "$arrayLength"

# EULA Window Display Logic
if [ "$EULAEnabled" = true ] ; then
    logStatus "$EULAStatus"
    logCommand ContinueButtonEULA "$EULAButton"
    while [ ! -f "$DEPNotifyUserInputPlist" ] ; do 
        debugLog "Waiting for user to accept EULA."
        /bin/sleep 1
    done
fi

# Registration Window Display Logic
if [ "$registrationEnabled" = true ] ; then
    logStatus "$registrationStatus"
    logCommand ContinueButtonRegister "$registrationButton"
    while [ ! -f "$DEPNotifyRegisterDoneFile" ]; do 
      debugLog "Waiting for user to complete registration."
      /bin/sleep 1
    done
    # Running Logic For Each Registration Box
    #if [ "$REG_TEXT_LABEL_1" != "" ]; then REG_TEXT_LABEL_1_LOGIC; fi
    #if [ "$REG_TEXT_LABEL_2" != "" ]; then REG_TEXT_LABEL_2_LOGIC; fi
    #if [ "$REG_POPUP_LABEL_1" != "" ]; then REG_POPUP_LABEL_1_LOGIC; fi
    #if [ "$REG_POPUP_LABEL_2" != "" ]; then REG_POPUP_LABEL_2_LOGIC; fi
    #if [ "$REG_POPUP_LABEL_3" != "" ]; then REG_POPUP_LABEL_3_LOGIC; fi
    #if [ "$REG_POPUP_LABEL_4" != "" ]; then REG_POPUP_LABEL_4_LOGIC; fi
fi

# Loop to run policies
for policy in "${policies[@]}" ; do
    logStatus "$(echo "$policy" | cut -d ',' -f1)"
    if [ "$testingMode" = true ]; then
        debugLog "Running policy '$(echo "$policy" | cut -d ',' -f2)'."
        /bin/sleep 10
    else 
        customTrigger="$(echo "$policy" | cut -d ',' -f2)"
        if [ "$customTrigger" != "$inventoryCustomTrigger" ]; then
            /usr/local/bin/jamf policy -event "$customTrigger" -forceNoRecon
        else
            /usr/local/bin/jamf policy -event "$customTrigger"
        fi
    fi
done

# Nice completion text
logStatus "$installCompleteText"
/usr/bin/touch "$DEPNotifyOnboarderDoneFile"

# Check to see if FileVault Deferred enablement is active
declare -r FVDeferredStatus="$(/usr/bin/fdesetup status | grep "Deferred" | cut -d ' ' -f6)"

# Logic to log user out if FileVault is detected. Otherwise, app will close.
if [ "$FVDeferredStatus" = active ] && [ "$testingMode" = true ] ; then
    if [ "$completeMethodDropdownAlert" = true ]; then
        logCommand Quit "This is typically where your 'FVLogoutText' would be displayed. However, 'testingMode' is set to true and FileVault deferred status is on."
    else
        logCommand MainText "'testingMode' is set to true and FileVault deferred status is on. Button effect is quit instead of logout. \n \n $FVCompleteMainText"
        logCommand ContinueButton "Test $FVCompleteButtonText"
    fi
elif [ "$FVDeferredStatus" = active ] && [ "$testingMode" = false ] ; then
    if [ "$completeMethodDropdownAlert" = true ]; then
        logCommand Logout "$FVAlertText"
    else
        logCommand MainText "$FVCompleteMainText"
        logCommand ContinueButtonLogout "$FVCompleteButtonText"
    fi
else
    if [ "$completeMethodDropdownAlert" = true ]; then
        logCommand Quit "$FVAlertText"
    else
        logCommand MainText "$FVCompleteMainText"
        logCommand ContinueButton "$FVCompleteButtonText"
    fi
fi

# Remove the DEPNotifyOnboarder script, Launch Daemon, and DEPNotify when onboarding is complete.
if [ "$selfDestruct" = true ] ; then
    waitForProcessToComplete "DEPNotify" -progressMessage "DEPNotify Still Running."
    /bin/rm -r /Applications/Utilities/DEPNotify.app
    /bin/rm "$DEPNotifyOnboarderLaunchDaemon"
    /bin/rm /usr/local/bin/DEPNotifyOnboarder.sh
fi

exit 0