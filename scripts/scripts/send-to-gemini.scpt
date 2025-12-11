tell application "Brave Browser"
    activate
    -- Optional: If you have multiple windows, ensure the front one is the target
    delay 0.1
    
    -- 1. Use JavaScript to force focus on the Prompt Text Area
    -- Gemini's input usually has 'rich-textarea' or 'contenteditable'
    execute front window's active tab javascript "
      const input = document.querySelector('div[contenteditable=\"true\"]') || document.querySelector('textarea');
      if (input) {
          input.focus();
      }
    "
end tell

tell application "System Events"
    tell process "Brave Browser"
        -- 2. Paste (Cmd+V)
        keystroke "v" using command down
        delay 0.2
        
        -- 3. Submit (Enter) - Optional: Comment out if you want to review before sending
        key code 36 
    end tell
end tell

delay 0.2

-- 4. Jump back to Emacs
tell application "Emacs"
    activate
end tell
