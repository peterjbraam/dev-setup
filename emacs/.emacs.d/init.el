;;; Init.el --- portable, devcontainer Emacs config  -*- lexical-binding: t; -*-

;; -------------------------------------------------------------------
;; PACKAGE BOOTSTRAP
;; -------------------------------------------------------------------

(require 'package)
(setq package-archives
      '(("gnu"   . "https://elpa.gnu.org/packages/")
        ("melpa" . "https://melpa.org/packages/")))

(package-initialize)
(unless (package-installed-p 'use-package)
  (package-refresh-contents) (package-install 'use-package))
(eval-when-compile (require 'use-package))
(setq use-package-always-ensure t)

;; -------------------------------------------------------------------
;; UI: FAST & READABLE
;; -------------------------------------------------------------------

(menu-bar-mode -1)
(when (display-graphic-p)
  (tool-bar-mode -1)
  (scroll-bar-mode -1))
(setq inhibit-startup-message t)
(global-display-line-numbers-mode 1)
(column-number-mode 1)
(setq-default indent-tabs-mode nil tab-width 4)

(load-theme 'wombat t)

(use-package which-key :init (which-key-mode 1))

;; -------------------------------------------------------------------
;; TERMINAL, MOUSE & CLIPBOARD
;; -------------------------------------------------------------------

(setenv "TERM" "xterm-256color")

;; Enable mouse interaction
(xterm-mouse-mode 1)
(mouse-wheel-mode 1)

;; Smooth scrolling
(setq mouse-wheel-scroll-amount '(1 ((shift) . 5)))
(setq mouse-wheel-progressive-speed nil)
(setq mouse-wheel-follow-mouse t)

;; Mouse bindings
(global-set-key [mouse-3] 'mouse-select-whole-line)
(global-set-key [mouse-1] 'mouse-set-point)
(global-set-key [down-mouse-1] 'mouse-drag-region)

(defun pb/reset-mouse ()
  "Toggle xterm-mouse-mode to reinitialize mouse handling."
  (interactive)
  (xterm-mouse-mode -1)
  (xterm-mouse-mode 1)
  (message "Mouse reset"))

;; --- Clippetty: Cross platform copy paste ---

(use-package clipetty
  :ensure t
  :config
  (clipetty-mode 1))

(unless (fboundp 'clipetty-copy)
  (defun clipetty-copy (text)
    "Compatibility shim: use kill-new so clipetty-mode can handle clipboard."
    (kill-new text)))

(unless (fboundp 'x-hide-tip)
  (defun x-hide-tip () (ignore)))

;; Advise clipetty for UTF-8
(defun pb/advice-clipetty-osc52-utf8 (orig-fun text &rest args)
  "Advise clipetty's OSC52 copy function to encode TEXT as UTF-8 first."
  (let ((utf8-text (encode-coding-string text 'utf-8)))
    (apply orig-fun utf8-text args)))

(when (fboundp 'clipetty--osc52-copy)
  (advice-add 'clipetty--osc52-copy :around #'pb/advice-clipetty-osc52-utf8)
  (message "Advised clipetty--osc52-copy for UTF-8 encoding."))

;; ;; Delayed Auto-Copy Logic
;; (defvar pb/auto-copy-idle-timer nil)

;; (defun pb/clipetty-sync-if-region ()
;;   "Copy region to system clipboard via clipetty if active."
;;   (when (use-region-p)
;;     (let ((text (buffer-substring-no-properties (region-beginning) (region-end))))
;;       (when (> (length text) 0)
;;         (clipetty-copy text)
;;         (message "-->Region copied to system clipboard (via clipetty)")))))

(defun pb/clipetty-delay-sync ()
  "Schedule delayed region sync."
  (when pb/auto-copy-idle-timer
    (cancel-timer pb/auto-copy-idle-timer))
  (setq pb/auto-copy-idle-timer
        (run-with-idle-timer 1.0 nil #'pb/clipetty-sync-if-region)))

(advice-add 'mouse-drag-region :after (lambda (&rest _) (pb/clipetty-delay-sync)))
(add-hook 'activate-mark-hook #'pb/clipetty-delay-sync)

;; -------------------------------------------------------------------
;; EDITING TOOLS (ENHANCED)
;; -------------------------------------------------------------------

(defun kill-to-end-of-buffer ()
  "Kill from point to the end of the buffer."
  (interactive)
  (kill-region (point) (point-max)))

(defun copy-whole-buffer ()
  "Copy the entire buffer to the kill ring."
  (interactive)
  (kill-new (buffer-substring-no-properties (point-min) (point-max)))
  (message "Entire buffer copied"))

;; Visual Undo
(use-package vundo
  :bind ("C-x u" . vundo)
  :config (setq vundo-glyph-alist vundo-unicode-symbols))

;; Structural Editing (Auto-close brackets)
(use-package smartparens
  :hook (prog-mode . smartparens-mode)
  :config (require 'smartparens-config))

;; Jump Navigation (Jump to char/line)
(use-package avy
  :bind (("C-:" . avy-goto-char)
         ("C-'" . avy-goto-line)))

;; Snippets
(use-package yasnippet
  :init (yas-global-mode 1))
(use-package yasnippet-snippets)

;; Wgrep (Editable Grep buffers)
(use-package wgrep)

;; --- SAFE FORMATTING UTILS (CRITICAL FIXES) ---

(defun pb/format-buffer-safely (command args)
  "Run COMMAND with ARGS on the entire buffer.
1. Checks exit code (Must be 0).
2. Checks output size (Must not be empty).
3. Uses delete/insert instead of replace-buffer-contents to prevent cursor/selection bugs."
  (let ((err-buf (get-buffer-create "*Formatter Errors*"))
        (patch-buf (get-buffer-create "*Formatter Output*"))
        (original-point (point))
        (original-window-start (window-start)))
    (with-current-buffer err-buf (erase-buffer))
    (with-current-buffer patch-buf (erase-buffer))
    
    ;; Run command on region
    (let ((exit-code (call-process-region (point-min) (point-max) command nil (list patch-buf err-buf) nil args)))
      
      ;; Safety Check: Exit code 0 AND output is not empty
      (if (and (zerop exit-code) (> (with-current-buffer patch-buf (buffer-size)) 0))
          (progn
            ;; Success: Replace content safely
            (delete-region (point-min) (point-max))
            (insert-buffer-substring patch-buf)
            
            ;; Restore state
            (goto-char original-point)
            (set-window-start nil original-window-start)
            (deactivate-mark) ;; Ensure no giant selection remains
            (message "Formatted with %s" command))
        
        ;; Failure: Do NOT touch buffer
        (message "Format skipped (Error or Empty Output): See *Formatter Errors*")))
    
    (kill-buffer patch-buf)))

;; -------------------------------------------------------------------
;; AUTO SAVING & BACKUPS
;; -------------------------------------------------------------------

(global-auto-revert-mode 1)
(setq global-auto-revert-non-file-buffers t)
(setq auto-revert-interval 2)
(setq auto-revert-check-vc-info t)

(setq auto-save-visited-interval 2)
(auto-save-visited-mode 1)
(setq make-backup-files nil create-lockfiles nil)

;; Custom Smart Backup Logic
;; -------------------------------------------------------------------
;; AUTO SAVING & BACKUPS
;; -------------------------------------------------------------------

;; Standard Auto-revert
(global-auto-revert-mode 1)
(setq global-auto-revert-non-file-buffers t)
(setq auto-revert-interval 2)
(setq auto-revert-check-vc-info t)

;; Standard Auto-save
(setq auto-save-visited-interval 2)
(auto-save-visited-mode 1)
(setq make-backup-files nil create-lockfiles nil)

;; --- Custom Smart Backup Logic ---

(defvar my-smart-backup-dir (expand-file-name "~/.emacs.d/timebackups/")
  "Directory to store smart timestamped backups.")

(defvar my-smart-backup-retention-hours 48
  "Delete backups older than this many hours.")

(defun my--backup-bucket ()
  "Return the appropriate backup time bucket symbol for current time."
  (let ((min (string-to-number (format-time-string "%M"))))
    (cond
     ((zerop (% min 2)) '2min)
     ((zerop (% min 5)) '5min)
     ((zerop (% min 20)) '20min)
     ((zerop (% min 60)) '1h)
     (t nil))))

(defun my--bucket-time-prefix (bucket)
  "Return a prefix regex to match backups in the same time bucket."
  (let ((file (file-name-nondirectory (or buffer-file-name ""))))
    (concat (regexp-quote (expand-file-name file my-smart-backup-dir))
            "\\."
            ;; Match the timestamp format: YYYYMMDD-HHMMSS
            ;; The regex groups vary to group backups by their bucket logic
            (pcase bucket
              ('2min "\\([0-9]\\{8\\}-[0-9]\\{4\\}\\)[0-9][0-9]") ;; Matches up to Minute digit 1
              ('5min "\\([0-9]\\{8\\}-[0-9]\\{4\\}\\)[0-9][0-9]")
              ('20min "\\([0-9]\\{8\\}-[0-9]\\{2\\}\\)[0-9][0-9][0-9][0-9]")
              ('1h   "\\([0-9]\\{8\\}-[0-9]\\{2\\}\\)[0-9][0-9]")
              (_     ".*"))
            "$")))

(defun my--cleanup-bucket-siblings (bucket)
  "Keep only the most recent file for the current time bucket."
  (let* ((file (file-name-nondirectory buffer-file-name))
         (prefix-re (my--bucket-time-prefix bucket))
         (backups (directory-files my-smart-backup-dir t prefix-re)))
    (when (> (length backups) 1)
      ;; Sort strings (filenames have timestamps, so string sort works)
      ;; Delete all but the last one (the newest)
      (dolist (f (butlast (sort backups #'string<)))
        (condition-case nil
            (delete-file f)
          (error nil))))))

(defun my-backup-run-gc ()
  "Aggressively clean up files older than 48 hours using system 'find'.
Running asynchronously to prevent Emacs from freezing on large directories."
  (interactive)
  (when (and (file-directory-p my-smart-backup-dir)
             (executable-find "find"))
    (let ((cmd (format "find %s -type f -mmin +%d -delete"
                       (shell-quote-argument (expand-file-name my-smart-backup-dir))
                       (* my-smart-backup-retention-hours 60))))
      (start-process-shell-command "backup-gc" "*backup-gc*" cmd)
      (message "Started background backup cleanup (older than %dh)..." 
               my-smart-backup-retention-hours))))

(defun my-smart-backup ()
  "Perform a timestamped backup for the current buffer."
  (when (and buffer-file-name (file-writable-p buffer-file-name))
    (let ((bucket (my--backup-bucket)))
      (when bucket
        (make-directory my-smart-backup-dir t)
        (let* ((file (file-name-nondirectory buffer-file-name))
               (stamp (format-time-string "%Y%m%d-%H%M%S"))
               (target (expand-file-name (format "%s.%s" file stamp) my-smart-backup-dir)))
          ;; Copy the file
          (copy-file buffer-file-name target t)
          ;; Clean up siblings in this specific bucket immediately
          (my--cleanup-bucket-siblings bucket)
          ;; (Optional) Log less frequently to avoid message spam
          (message "Smart backup: %s [%s]" target bucket))))))

;; Run per-buffer backups every minute
(run-with-timer 10 60 (lambda () 
                        (save-excursion
                          (dolist (buf (buffer-list))
                            (with-current-buffer buf
                              (when (buffer-file-name)
                                (my-smart-backup)))))))

;; Run Global Garbage Collection every hour (cleans files > 48h old)
(run-with-timer 120 3600 #'my-backup-run-gc)

;; Run GC once on startup (after 5 seconds) to clear the initial 100k mess
(run-with-timer 5 nil #'my-backup-run-gc)

;; Disable autosaving for build modes
(add-hook 'makefile-gmake-mode-hook
          (lambda () (setq-local auto-save-visited-mode nil)))
(add-hook 'compilation-mode-hook
          (lambda () (setq-local auto-save-visited-mode nil)))

(defun my-backup-restore ()
  "Find backups for the current file and diff them using Ediff."
  (interactive)
  (unless buffer-file-name
    (user-error "Current buffer is not visiting a file"))
  
  (let* ((filename (file-name-nondirectory buffer-file-name))
         ;; Search for files starting with "filename." in the backup dir
         (backup-files (directory-files my-smart-backup-dir t 
                                        (concat "^" (regexp-quote filename) "\\.")))
         (options (mapcar (lambda (f)
                            ;; Format option as: "filename (timestamp)"
                            (cons (format "%s  (%s)" 
                                          (file-name-nondirectory f)
                                          (format-time-string "%Y-%m-%d %H:%M:%S" 
                                                              (nth 5 (file-attributes f))))
                                  f))
                          ;; Sort by modification time (newest first)
                          (sort backup-files #'file-newer-than-file-p))))
    
    (if (null options)
        (message "No backups found for %s" filename)
      
      ;; Use completing-read (which uses Vertico/Orderless) to pick a backup
      (let* ((choice (completing-read "Diff with backup: " (mapcar #'car options)))
             (selected-file (cdr (assoc choice options))))
        
        ;; Open the backup and start Ediff
        (if (file-exists-p selected-file)
            (ediff-files buffer-file-name selected-file)
          (message "Backup file missing!"))))))

;; -------------------------------------------------------------------
;; CONTAINERS & TRAMP
;; -------------------------------------------------------------------

(require 'tramp-container)

;; -------------------------------------------------------------------
;; AI CHAT TOOLS
;; -------------------------------------------------------------------

(defun ai-new-prompt ()
  "Open a new AI prompt buffer with timestamp header."
  (interactive)
  (let* ((buf (get-buffer-create "*ai-prompt*"))
         (ts (format-time-string "%a %b %d %H:%M:%S %Z %Y")))
    (switch-to-buffer buf)
    (erase-buffer)
    (insert (format "%s  Prompt:\n\n" ts))
    (markdown-mode)
    (message "--> Type your prompt, then press C-c s to append diff, copy, and close.")))

(defun ai-append-diff-and-copy ()
  "Append ai-diff output, copy to clipboard, log, and close."
  (interactive)
  (let* ((context (string-trim
                   (with-temp-buffer
                     (condition-case nil (insert-file-contents "~/.ai-context") (error ""))
                     (buffer-string))))
         (tempfile (make-temp-file "ai-diff"))
         (chatlog (concat (expand-file-name "~/ai/") context "-ai/docs/chats/current.txt"))
         (ts (format-time-string "%a %b %d %H:%M:%S %Z %Y")))
    (insert (format "\n\n### DIFF (%s)\n\n" ts))
    (call-process-shell-command (concat "~/scripts/ai-diff.sh > " tempfile))
    (insert-file-contents tempfile)
    (when (file-exists-p chatlog)
      (with-temp-buffer
        (insert (format "--- %s ---\n" (format-time-string "%Y-%m-%d %H:%M:%S")))
        (insert-file-contents tempfile)
        (append-to-file (point-min) (point-max) chatlog)))
    (kill-new (buffer-string))
    (delete-file tempfile)
    (message "--> Prompt + diff copied to clipboard, logged, and buffer closed.")
    (kill-buffer (current-buffer))))

(defun ai-apply-patch-from-clipboard ()
  "Apply a unified diff patch from the clipboard using Ediff."
  (interactive)
  (let* ((patch-text (shell-command-to-string "pbpaste"))
         (patch-buf (generate-new-buffer "*AI Patch*")))
    (if (or (not patch-text) (string-empty-p patch-text))
        (message "Clipboard is empty or not a diff.")
      (with-current-buffer patch-buf
        (insert patch-text)
        (goto-char (point-min)))
      (message "Launching Ediff for AI patch...")
      (ediff-patch-buffer patch-buf nil t)
      (add-hook 'ediff-quit-hook
                (lambda () (when (buffer-live-p patch-buf) (kill-buffer patch-buf)))
                nil t))))

(setq ediff-keep-variants nil)
(setq ediff-make-buffers-readonly-at-startup nil)
(setq ediff-quit-hook
      (lambda ()
        (when (y-or-n-p "Revert all modified buffers? ")
          (mapc #'(lambda (buf) (when (buffer-live-p buf) (with-current-buffer buf (revert-buffer t t t))))
                (list ediff-buffer-A ediff-buffer-B ediff-buffer-C)))))

(defun pb/send-prompt-to-brave ()
  "Copy the current prompt (defined by boundaries) and send to Brave/Gemini."
  (interactive)
  (let ((prompt-text (pb/get-current-prompt-text)))
    (if (string-empty-p prompt-text)
        (message "No prompt found!")
      ;; 1. Copy to system clipboard
      (kill-new prompt-text)
      ;; 2. Run the AppleScript
      (call-process-shell-command "osascript ~/scripts/send-to-gemini.scpt")
      (message "Prompt sent to Gemini."))))

(defun pb/get-current-prompt-text ()
  "Extract text between the last '---' separator and point."
  (save-excursion
    (let ((end (point))
          (beg (progn
                 (if (re-search-backward "^---" nil t)
                     (line-beginning-position 2) ;; Start after the dashes
                   (point-min)))))
      (string-trim (buffer-substring-no-properties beg end)))))


;; -------------------------------------------------------------------
;; NAVIGATION & COMPLETION
;; -------------------------------------------------------------------

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles orderless partial-completion)))))

(use-package vertico :init (vertico-mode 1) :custom (vertico-cycle t))
(use-package marginalia :init (marginalia-mode 1))
(use-package consult)

(use-package embark
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim))
  :init (setq prefix-help-command #'embark-prefix-help-command))
(use-package embark-consult :hook (embark-collect-mode . consult-preview-at-point-mode))

(use-package corfu :init (global-corfu-mode 1) :custom (corfu-auto t))
(use-package kind-icon
  :after corfu
  :custom (kind-icon-default-face 'corfu-default)
  :config (add-to-list 'corfu-margin-formatters #'kind-icon-margin-formatter))

;; Projects
(use-package projectile
  :init (projectile-mode 1)
  :custom ((projectile-enable-caching t)
           (projectile-git-submodule-command "git submodule --quiet foreach 'echo $sm_path'"))
  :bind-keymap ("C-c p" . projectile-command-map))

;; -------------------------------------------------------------------
;; BUILD & GIT
;; -------------------------------------------------------------------

(use-package vterm :when (not (eq system-type 'windows-nt)))
(setq compilation-scroll-output t)

(use-package magit :commands (magit-status magit-dispatch))
(use-package diff-hl
  :hook ((prog-mode . diff-hl-mode)
         (magit-post-refresh . diff-hl-magit-post-refresh)))

;; -------------------------------------------------------------------
;; LANGUAGES & LSP
;; -------------------------------------------------------------------

(use-package lsp-mode
  :commands (lsp lsp-deferred)
  :custom
  (lsp-prefer-flymake nil)
  (lsp-completion-provider :none)
  ;; CRITICAL: Disable all LSP auto-formatting. We use our own safe wrapper.
  (lsp-enable-on-type-formatting nil)
  (lsp-before-save-edits nil))

(use-package lsp-ui :commands lsp-ui-mode)
(use-package flycheck :init (global-flycheck-mode 1))

;; --- Markdown ---
(defun pb/yank-markdown-code-block ()
  "If point is inside a fenced code block, yank its contents."
  (interactive)
  (save-excursion
    (when (re-search-backward "^```" nil t)
      (let ((beg (match-end 0)))
        (when (re-search-forward "^```" nil t)
          (let ((end (match-beginning 0)))
            (kill-new (buffer-substring-no-properties beg end))
            (message "Code block yanked.")))))))

(defun pb/markdown-outline-setup ()
  (setq-local outline-regexp "^\\(#{1,6}\\)\\s-+\\(.+\\)$")
  (outline-minor-mode 1))

(use-package markdown-mode
  :mode (("\\.md\\'" . markdown-mode) ("README\\.md\\'" . gfm-mode))
  :custom (markdown-command "pandoc")
  :hook ((markdown-mode . lsp-deferred)
         (markdown-mode . pb/markdown-outline-setup))
  :config
  (define-key markdown-mode-map (kbd "<tab>")    #'markdown-cycle)
  (define-key markdown-mode-map (kbd "S-<tab>")  #'markdown-shifttab))

;; --- Go ---
(defun pb/go-format-buffer ()
  (interactive)
  (when (eq major-mode 'go-mode)
    (cond ((executable-find "goimports") (pb/format-buffer-safely "goimports" nil))
          ((executable-find "gofmt") (pb/format-buffer-safely "gofmt" nil)))))

(use-package go-mode
  :mode "\\.go\\'"
  :hook ((go-mode . lsp-deferred)
         ;; Double safety: explicit local disable of LSP formatting
         (go-mode . (lambda ()
                      (setq-local lsp-enable-on-type-formatting nil)
                      (setq-local lsp-before-save-edits nil)
                      (add-hook 'before-save-hook #'pb/go-format-buffer nil t)))))

;; --- JSON ---
(defun pb/json-format-buffer ()
  (interactive)
  (when (and (eq major-mode 'json-mode) (executable-find "jq"))
    (pb/format-buffer-safely "jq" ".")))

(use-package json-mode
  :mode "\\.json\\'"
  :hook ((json-mode . lsp-deferred)
         (json-mode . (lambda () (add-hook 'before-save-hook #'pb/json-format-buffer nil t)))))

;; --- YAML ---
(defun pb/yaml-format-buffer ()
  (interactive)
  (when (and (derived-mode-p 'yaml-mode) (executable-find "yamlfmt"))
    (pb/format-buffer-safely "yamlfmt" nil)))

(use-package yaml-mode
  :ensure t :mode ("\\.ya?ml\\'" . yaml-mode)
  :hook ((yaml-mode . lsp-deferred)
         (yaml-mode . (lambda () (add-hook 'before-save-hook #'pb/yaml-format-buffer nil t)))))

(flycheck-define-checker yaml-yamllint
  "A YAML syntax and style checker using yamllint."
  :command ("yamllint" "-f" "parsable" source)
  :error-patterns
  ((warning line-start (file-name) ":" line ":" column ": " (id (one-or-more not-newline) ":") (message) line-end))
  :modes (yaml-mode))
(add-to-list 'flycheck-checkers 'yaml-yamllint)

;; --- Swift ---
(defun pb/swift-format-buffer ()
  (interactive)
  (when (and (eq major-mode 'swift-mode) (executable-find "swift-format"))
    (pb/format-buffer-safely "swift-format" "format --stdin --quiet")))

(use-package swift-mode
  :ensure t
  :hook ((swift-mode . lsp)
         (swift-mode . (lambda () (add-hook 'before-save-hook #'pb/swift-format-buffer nil t))))
  :init
  (setq lsp-sourcekit-executable "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp"))

;; --- Rust ---
(use-package rust-mode :ensure t :hook (rust-mode . lsp))
(setq rust-format-on-save t)
(with-eval-after-load 'lsp-mode (setq lsp-rust-server 'rust-analyzer))

;; --- Docker, Shell, Bazel, Makefile, RPM ---
(use-package dockerfile-mode :ensure t :mode "\\.docker\\'")
(add-hook 'sh-mode-hook 'lsp-deferred)
(use-package bazel :mode (("\\.bzl\\'" . bazel-mode) ("WORKSPACE\\'" . bazel-workspace-mode) ("BUILD\\(\\.bazel\\)?\\'" . bazel-build-mode)))
(add-to-list 'auto-mode-alist '("Makefile\\'" . makefile-gmake-mode))
(use-package rpm-spec-mode :mode "\\.spec\\'")

(flycheck-define-checker rpmlint
  "Lint RPM spec files with rpmlint."
  :command ("rpmlint" "-i" source)
  :error-patterns ((error line-start (file-name) ":" line ": E: " (message) line-end)
                   (warning line-start (file-name) ":" line ": W: " (message) line-end)
                   (info line-start (file-name) ":" line ": I: " (message) line-end))
  :modes (rpm-spec-mode)
  :predicate (lambda () (executable-find "rpmlint")))
(add-to-list 'flycheck-checkers 'rpmlint)

;; --- Debian & Others ---
(use-package debian-el
  :mode (("debian/control\\'" . debian-control-mode) ("debian/changelog\\'" . debian-changelog-mode) ("debian/rules\\'" . makefile-gmake-mode)))

(flycheck-define-checker lintian
  "Run lintian on debian files."
  :command ("bash" "-lc" "lintian --no-cfg --info --display-info --pedantic . 2>&1 || true")
  :error-patterns ((error line-start (any "E" "X") ": " (message) line-end)
                   (warning line-start "W: " (message) line-end)
                   (info line-start "I: " (message) line-end))
  :modes (debian-control-mode debian-changelog-mode)
  :working-directory (lambda (_) default-directory)
  :predicate (lambda () (executable-find "lintian")))
(add-to-list 'flycheck-checkers 'lintian)

(add-to-list 'auto-mode-alist '("Brewfile\\'" . ruby-mode))
(flycheck-define-checker brew-bundle
  "Check Brewfile bundle status."
  :command ("brew" "bundle" "check" "--file" source)
  :error-patterns ((warning line-start (message "Warning:" (one-or-more not-newline)) line-end)
                   (error line-start "Error: " (message (one-or-more not-newline)) line-end))
  :modes (ruby-mode)
  :predicate (lambda () (and buffer-file-name (string-match-p "Brewfile\\'" buffer-file-name))))
(add-to-list 'flycheck-checkers 'brew-bundle)

(add-to-list 'auto-mode-alist '("apt-packages\\.txt\\'" . conf-mode))
(add-to-list 'auto-mode-alist '("rpm-packages\\.txt\\'" . conf-mode))
(flycheck-define-checker apt-package-list
  "Check existence of apt packages in list."
  :command ("bash" "-lc" "awk 'BEGIN{rc=0} /^[#[:space:]]*$/ {next} {cmd=\"apt-cache show \"$1\" >/dev/null 2>&1\"; rc=system(cmd); if (rc!=0){print NR\":\"$1}}' ${INPUT}" source)
  :error-patterns ((error line-start line ":" (message) line-end))
  :modes (conf-mode)
  :predicate (lambda () (and (executable-find "apt-cache") (string-match-p "apt-packages\\.txt\\'" (buffer-name)))))
(add-to-list 'flycheck-checkers 'apt-package-list)

;; -------------------------------------------------------------------
;; MISC & PROCESS CLEANUP
;; -------------------------------------------------------------------

(defun my/disable-process-query ()
  (dolist (proc (process-list))
    (when (member (process-name proc) '("pbcopy" "bash" "sh"))
      (set-process-query-on-exit-flag proc nil))))
(add-hook 'kill-emacs-hook #'my/disable-process-query)

;; -------------------------------------------------------------------
;; GLOBAL KEY BINDINGS
;; -------------------------------------------------------------------

(global-set-key (kbd "C-x C-c") 'kill-emacs)
(global-set-key (kbd "C-<tab>") #'mode-line-other-buffer)

;; --- Enhanced Bindings ---
(global-set-key (kbd "C-x u") 'vundo)          ; Visual Undo (Tree view)
(global-set-key (kbd "M-s r") 'consult-ripgrep) ; Search project text (Grep)
(global-set-key (kbd "M-s l") 'consult-line)    ; Search current file lines
(global-set-key (kbd "C-x f") 'projectile-find-file) ; Fuzzy file search

;; AI tools
(global-set-key (kbd "C-c f") 'ai-apply-patch-from-clipboard)
(global-set-key (kbd "C-c q") 'ai-new-prompt)
(global-set-key (kbd "C-c s") 'ai-append-diff-and-copy)

;; Edit utilities
(global-set-key (kbd "C-c k") 'kill-to-end-of-buffer)
(global-set-key (kbd "C-c a") 'copy-whole-buffer)
(global-set-key (kbd "C-c y") #'pb/yank-markdown-code-block)

;; Magit
(global-set-key (kbd "C-x g") 'magit-status)

;; Search restore
(global-set-key (kbd "C-s") #'isearch-forward)
(global-set-key (kbd "C-r") #'isearch-backward)


;; Suggested Binding (Add to Global Key Bindings)
(global-set-key (kbd "C-c b") 'my-backup-restore)
(defun pb/send-prompt-to-brave ()
  "Copy the current prompt (defined by boundaries) and send to Brave/Gemini."
  (interactive)
  (let ((prompt-text (pb/get-current-prompt-text)))
    (if (string-empty-p prompt-text)
        (message "No prompt found!")
      ;; 1. Copy to system clipboard
      (kill-new prompt-text)
      ;; 2. Run the AppleScript
      (call-process-shell-command "osascript ~/scripts/send-to-gemini.scpt")
      (message "Prompt sent to Gemini."))))

(defun pb/get-current-prompt-text ()
  "Extract text between the last '---' separator and point."
  (save-excursion
    (let ((end (point))
          (beg (progn
                 (if (re-search-backward "^---" nil t)
                     (line-beginning-position 2) ;; Start after the dashes
                   (point-min)))))
      (string-trim (buffer-substring-no-properties beg end)))))

;; Keybinding
(global-set-key (kbd "C-c g") 'pb/send-prompt-to-brave)(defun pb/send-prompt-to-brave ()
  "Copy the current prompt (defined by boundaries) and send to Brave/Gemini."
  (interactive)
  (let ((prompt-text (pb/get-current-prompt-text)))
    (if (string-empty-p prompt-text)
        (message "No prompt found!")
      ;; 1. Copy to system clipboard
      (kill-new prompt-text)
      ;; 2. Run the AppleScript
      (call-process-shell-command "osascript ~/scripts/send-to-gemini.scpt")
      (message "Prompt sent to Gemini."))))

(defun pb/get-current-prompt-text ()
  "Extract text between the last '---' separator and point."
  (save-excursion
    (let ((end (point))
          (beg (progn
                 (if (re-search-backward "^---" nil t)
                     (line-beginning-position 2) ;; Start after the dashes
                   (point-min)))))
      (string-trim (buffer-substring-no-properties beg end)))))

;; Keybinding
(global-set-key (kbd "C-c g") 'pb/send-prompt-to-brave)(defun pb/send-prompt-to-brave ()
  "Copy the current prompt (defined by boundaries) and send to Brave/Gemini."
  (interactive)
  (let ((prompt-text (pb/get-current-prompt-text)))
    (if (string-empty-p prompt-text)
        (message "No prompt found!")
      ;; 1. Copy to system clipboard
      (kill-new prompt-text)
      ;; 2. Run the AppleScript
      (call-process-shell-command "osascript ~/scripts/send-to-gemini.scpt")
      (message "Prompt sent to Gemini."))))

(defun pb/get-current-prompt-text ()
  "Extract text between the last '---' separator and point."
  (save-excursion
    (let ((end (point))
          (beg (progn
                 (if (re-search-backward "^---" nil t)
                     (line-beginning-position 2) ;; Start after the dashes
                   (point-min)))))
      (string-trim (buffer-substring-no-properties beg end)))))

;; Keybinding
(global-set-key (kbd "C-c g") 'pb/send-prompt-to-brave)(defun pb/send-prompt-to-brave ()
  "Copy the current prompt (defined by boundaries) and send to Brave/Gemini."
  (interactive)
  (let ((prompt-text (pb/get-current-prompt-text)))
    (if (string-empty-p prompt-text)
        (message "No prompt found!")
      ;; 1. Copy to system clipboard
      (kill-new prompt-text)
      ;; 2. Run the AppleScript
      (call-process-shell-command "osascript ~/scripts/send-to-gemini.scpt")
      (message "Prompt sent to Gemini."))))

(defun pb/get-current-prompt-text ()
  "Extract text between the last '---' separator and point."
  (save-excursion
    (let ((end (point))
          (beg (progn
                 (if (re-search-backward "^---" nil t)
                     (line-beginning-position 2) ;; Start after the dashes
                   (point-min)))))
      (string-trim (buffer-substring-no-properties beg end)))))

;; Keybinding
(global-set-key (kbd "C-c g") 'pb/send-prompt-to-brave)(defun pb/send-prompt-to-brave ()
  "Copy the current prompt (defined by boundaries) and send to Brave/Gemini."
  (interactive)
  (let ((prompt-text (pb/get-current-prompt-text)))
    (if (string-empty-p prompt-text)
        (message "No prompt found!")
      ;; 1. Copy to system clipboard
      (kill-new prompt-text)
      ;; 2. Run the AppleScript
      (call-process-shell-command "osascript ~/scripts/send-to-gemini.scpt")
      (message "Prompt sent to Gemini."))))

(defun pb/get-current-prompt-text ()
  "Extract text between the last '---' separator and point."
  (save-excursion
    (let ((end (point))
          (beg (progn
                 (if (re-search-backward "^---" nil t)
                     (line-beginning-position 2) ;; Start after the dashes
                   (point-min)))))
      (string-trim (buffer-substring-no-properties beg end)))))

;;============================================
;; DIRVISH
;;============================================


(use-package dirvish
  :init
  (dirvish-override-dired-mode) ;; Let Dirvish take over C-x d
  :custom
  (dirvish-quick-access-entries ;; Quick shortcuts in the header
   '(("h" "~/"                          "Home")
     ("d" "~/Downloads/"                "Downloads")
     ("m" "/mnt/"                       "Drives")
     ("t" "~/.local/share/Trash/files/" "Trash")))
  (dirvish-mode-line-format
   '(:left (sort symlink) :right (omit yank index)))
  (dirvish-attributes
   '(all-the-icons file-time file-size collapse subtree-state vc-state git-msg))
  :config
  (setq dirvish-header-line-format '(:left (path) :right (free-space)))
  (setq dired-listing-switches "-agho --group-directories-first")
  :bind ; Bind specific Dirvish features
  (("C-c f" . dirvish-fd)    ; Fast file search in current dir
   :map dirvish-mode-map
   ("a"   . dirvish-quick-access)
   ("f"   . dirvish-file-info-menu)
   ("y"   . dirvish-yank-menu)
   ("N"   . dirvish-narrow)
   ("^"   . dirvish-history-last)
   ("h"   . dirvish-history-jump) ; Go back in history
   ("s"   . dirvish-quicksort)    ; Sort by size/time/ext
   ("TAB" . dirvish-subtree-toggle) ; Expand dir inline like a tree
   ("M-f" . dirvish-history-go-forward)
   ("M-b" . dirvish-history-go-backward)
   ("M-l" . dirvish-ls-switches-menu)
   ("M-m" . dirvish-mark-menu)
   ("M-t" . dirvish-layout-toggle)
   ("M-s" . dirvish-setup-menu)
   ("M-e" . dirvish-emerge-menu)
   ("M-j" . dirvish-fd-jump)))


;;===============================================
;; KEYBINDINGS
;;===============================================


;; Keybinding
(global-set-key (kbd "C-c g") 'pb/send-prompt-to-brave)

;; Misc
(global-set-key (kbd "C-c m") 'pb/reset-mouse)
(global-set-key (kbd "C-c C-m") (lambda () (interactive) (compile "make -k")))

(provide 'init)
;;; init.el ends here

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages nil))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
