on run argv
  set operation to item 1 of argv
  tell application "iTerm"
    if operation is "describe" or operation is "current" then
      set target to current session of current window
      tell target to set currentJob to variable named "session.jobName"
      if operation is "current" or currentJob is "herdr" then
        return (unique id of target) & "|" & (profile name of target)
      end if
      set hosts to {}
      repeat with w in windows
        repeat with t in tabs of w
          repeat with s in sessions of t
            tell s to set jobName to variable named "session.jobName"
            if jobName is "herdr" then set end of hosts to s
          end repeat
        end repeat
      end repeat
      if (count of hosts) is 1 then
        set target to item 1 of hosts
      else
        error "Focus the Herdr terminal before launching jvim"
      end if
      return (unique id of target) & "|" & (profile name of target)
    end if
  end tell
end run
