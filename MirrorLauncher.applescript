on run
  set appPath to POSIX path of (path to me)
  set runtimePath to quoted form of (appPath & "Contents/Resources/mirror-runtime.sh")

  try
    do shell script runtimePath
  on error errorMessage number errorNumber
    display dialog errorMessage buttons {"OK"} default button "OK" with title "Mirror" with icon caution
  end try
end run
