on open location targetURL
  do shell script (quoted form of (POSIX path of (path to home folder) & ".local/bin/jvim-open-location")) & " " & quoted form of targetURL
end open location
