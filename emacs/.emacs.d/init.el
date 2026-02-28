;; Init.el --- portable, devcontainer Emacs config  -*- lexical-binding: t; -*-
;; Commentary
;; -------------------------------------------------------------------
;; 1. CRITICAL COMPATIBILITY FIXES (Must run first)
;; -------------------------------------------------------------------

;; Fix for "Symbol's function definition is void: x-hide-tip"
;; Prevents crashes when lsp-ui tries to close tooltips in a terminal.
(unless (fboundp 'x-hide-tip)
  (defalias 'x-hide-tip #'ignore))

;; -------------------------------------------------------------------
;; 2. PACKAGE BOOTSTRAP
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
;; 3. UI & TERMINAL SETTINGS
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

;; Mouse Support (xterm)
(setenv "TERM" "xterm-256color")
(xterm-mouse-mode 1)
(mouse-wheel-mode 1)
(setq mouse-wheel-scroll-amount '(1 ((shift) . 5)))
(setq mouse-wheel-progressive-speed nil)
(setq mouse-wheel-follow-mouse t)

(defun pb/reset-mouse ()
  "Toggle xterm-mouse-mode to reinitialize mouse handling."
  (interactive)
  (xterm-mouse-mode -1)
  (xterm-mouse-mode 1)
  (message "Mouse reset"))

;; -------------------------------------------------------------------
;; 3. CLIPBOARD LOGIC (Manual Copy / Auto Paste)
;; -------------------------------------------------------------------

;; 1. Force Load Clipetty immediately (so functions are available)
(use-package clipetty 
  :ensure t 
  :demand t)

;; 2. Disable standard clipboard sync (Keeps C-k/C-w local and fast)
(setq interprogram-cut-function nil)

;; 3. Enable auto-pasting (C-y checks system clipboard)
(setq interprogram-paste-function
      (lambda ()
        (when (fboundp 'clipetty-read)
          (clipetty-read))))

;; 4. Explicit Copy to System (M-w only) WITH FALLBACK
(defun pb/copy-region-and-sync (beg end)
  "Copy region to kill-ring AND sync to system clipboard."
  (interactive "r")
  ;; A. Internal Emacs Copy
  (cond
   ((and (minibufferp) (not (use-region-p)))
    (kill-new (minibuffer-contents)))
   (t
    (kill-ring-save beg end)))
  
  ;; B. System Sync (The Robust Part)
  (cond
   ;; Option 1: Try Clipetty (Best for Remote/SSH/Docker)
   ((fboundp 'clipetty-copy)
    (clipetty-copy (car kill-ring))
    (message "Copied to System (via Clipetty)."))
   
   ;; Option 2: Fallback to pbcopy (Best for Local Mac)
   ((executable-find "pbcopy")
    (let ((process-connection-type nil))
      (let ((proc (start-process "pbcopy" nil "pbcopy")))
        (process-send-string proc (car kill-ring))
        (process-send-eof proc)))
    (message "Copied to System (via pbcopy)."))
   
   ;; Option 3: Failure
   (t
    (message "Copied to Ring (System clipboard unavailable)."))))

;; -------------------------------------------------------------------
;; 5. CUSTOM FUNCTIONS (Tools & Workflows)
;; -------------------------------------------------------------------

;; --- A. Text Manipulation ---
(defun kill-to-end-of-buffer ()
  (interactive)
  (kill-region (point) (point-max)))

(defun copy-whole-buffer ()
  (interactive)
  (kill-new (buffer-substring-no-properties (point-min) (point-max)))
  (message "Entire buffer copied"))

(defun pb/format-buffer-safely (command args)
  "Run formatter safely without deleting buffer on failure."
  (let ((err-buf (get-buffer-create "*Formatter Errors*"))
        (patch-buf (get-buffer-create "*Formatter Output*"))
        (original-point (point))
        (original-window-start (window-start)))
    (with-current-buffer err-buf (erase-buffer))
    (with-current-buffer patch-buf (erase-buffer))
    (let ((exit-code (call-process-region (point-min) (point-max) command nil (list patch-buf err-buf) nil args)))
      (if (and (zerop exit-code) (> (with-current-buffer patch-buf (buffer-size)) 0))
          (progn
            (delete-region (point-min) (point-max))
            (insert-buffer-substring patch-buf)
            (goto-char original-point)
            (set-window-start nil original-window-start)
            (deactivate-mark)
            (message "Formatted with %s" command))
        (message "Format skipped (Error or Empty Output): See *Formatter Errors*")))
    (kill-buffer patch-buf)))

;; --- B. AI Ghost Text (The "Terminal Safe" Version) ---
(defvar my-ghost-overlay nil "Holds the current AI ghost overlay.")

(defun my/clear-ghost-text ()
  "Remove the ghost text if it exists."
  (interactive)
  (when (and my-ghost-overlay (overlayp my-ghost-overlay))
    (delete-overlay my-ghost-overlay)
    (setq my-ghost-overlay nil)))

(defun ai-demo-ghost-text ()
  "Display a fake AI prediction at the END of the current line."
  (interactive)
  (my/clear-ghost-text)
  (let* ((line-end (line-end-position))
         (has-newline (< line-end (point-max))))
    (if (not has-newline)
        (message "Add a newline to the end of the file first!")
      ;; Create overlay on the newline character
      (setq my-ghost-overlay (make-overlay line-end (1+ line-end)))
      ;; Replace '\n' with '...prediction...\n'
      (let ((ghost-string "  <-- [AI says: return True]"))
        (overlay-put my-ghost-overlay 'display 
                     (concat (propertize ghost-string 
                                         'face '(:foreground "#50FA7B" :slant italic)) 
                             "\n")))
      ;; Auto-Clear on next keystroke
      (letrec ((clear-hook 
                (lambda () 
                  (my/clear-ghost-text)
                  (remove-hook 'pre-command-hook clear-hook))))
        (add-hook 'pre-command-hook clear-hook)))))

;; --- C. AI Tools (Prompting) ---
(defun ai-new-prompt ()
  (interactive)
  (let* ((buf (get-buffer-create "*ai-prompt*"))
         (ts (format-time-string "%a %b %d %H:%M:%S %Z %Y")))
    (switch-to-buffer buf)
    (erase-buffer)
    (insert (format "%s  Prompt:\n\n" ts))
    (markdown-mode)
    (message "Type prompt, then C-c s to save/copy.")))

(defun ai-append-diff-and-copy ()
  (interactive)
  (let* ((context (string-trim (with-temp-buffer (condition-case nil (insert-file-contents "~/.ai-context") (error "")) (buffer-string))))
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
    (message "Prompt + diff copied to clipboard.")
    (kill-buffer (current-buffer))))

(defun ai-apply-patch-from-clipboard ()
  (interactive)
  (let* ((patch-text (shell-command-to-string "pbpaste"))
         (patch-buf (generate-new-buffer "*AI Patch*")))
    (if (or (not patch-text) (string-empty-p patch-text))
        (message "Clipboard is empty.")
      (with-current-buffer patch-buf (insert patch-text) (goto-char (point-min)))
      (ediff-patch-buffer patch-buf nil t)
      (add-hook 'ediff-quit-hook (lambda () (when (buffer-live-p patch-buf) (kill-buffer patch-buf))) nil t))))

(defun pb/send-prompt-to-brave ()
  (interactive)
  (let ((prompt-text (pb/get-current-prompt-text)))
    (if (string-empty-p prompt-text)
        (message "No prompt found!")
      (kill-new prompt-text)
      (call-process-shell-command "osascript ~/scripts/send-to-gemini.scpt")
      (message "Prompt sent to Gemini."))))

(defun pb/get-current-prompt-text ()
  (save-excursion
    (let ((end (point))
          (beg (progn (if (re-search-backward "^---" nil t) (line-beginning-position 2) (point-min)))))
      (string-trim (buffer-substring-no-properties beg end)))))

;; --- D. Review Workflow (F5-F8) ---
(defun my/delete-note-and-next ()
  "INSTANTLY trash current file, kill buffer, and jump to next result."
  (interactive)
  (let ((filename (buffer-file-name))
        (current-buf (current-buffer)))
    (if (not filename)
        (message "Buffer is not visiting a file!")
      ;; 1. Trash the file (No confirmation!)
      (move-file-to-trash filename)
      (message "Trashed: %s" (file-name-nondirectory filename))
      ;; 2. Jump to next note in the list
      (condition-case nil
          (next-error)
        (error (message "End of list!")))
      ;; 3. Kill the old buffer
      (kill-buffer current-buf))))

;; --- E. Smart Backups & Timeline ---
(global-auto-revert-mode 1)
(setq global-auto-revert-non-file-buffers t)
(auto-save-visited-mode 1)
(setq auto-save-visited-interval 2)
(setq make-backup-files nil create-lockfiles nil)

(defvar my-smart-backup-dir (expand-file-name "~/.emacs.d/timebackups/"))

(defun my-smart-backup ()
  (when (and buffer-file-name (file-writable-p buffer-file-name))
    (let ((min (string-to-number (format-time-string "%M"))))
      ;; Simple logic: Backup if minute is even (every 2 mins)
      (when (zerop (% min 2))
        (make-directory my-smart-backup-dir t)
        (let* ((file (file-name-nondirectory buffer-file-name))
               (stamp (format-time-string "%Y-%m-%d-%H:%M:%S"))
               (target (expand-file-name (format "%s.%s" file stamp) my-smart-backup-dir)))
          (copy-file buffer-file-name target t))))))

(run-with-timer 10 60 (lambda () (save-excursion (dolist (buf (buffer-list)) (with-current-buffer buf (when (buffer-file-name) (my-smart-backup)))))))

;; Backup Timeline UI
(define-derived-mode backup-timeline-mode special-mode "BackupTimeline" (setq truncate-lines t))
(defun my-backup-timeline ()
  (interactive)
  (unless buffer-file-name (user-error "No file"))
  (let* ((target (expand-file-name buffer-file-name))
         (filename (file-name-nondirectory target))
         (backups (sort (directory-files my-smart-backup-dir t (concat "^" (regexp-quote filename) "\\.")) #'string<))
         (buf (get-buffer-create "*Backup Timeline*")))
    (with-current-buffer buf
      (setq buffer-read-only nil) (erase-buffer)
      (setq-local backup-timeline--target target)
      (setq-local backup-timeline--dir my-smart-backup-dir)
      (insert (format "Backups for: %s\n\n" filename))
      (dolist (f backups) (insert (file-name-nondirectory f) "\n"))
      (backup-timeline-mode))
    (pop-to-buffer buf)))

(defun backup-timeline-preview ()
  (interactive)
  (let ((file (expand-file-name (string-trim (thing-at-point 'line t)) backup-timeline--dir)))
    (when (file-exists-p file) (ediff-files backup-timeline--target file))))

(defun my-backup-restore ()
  (interactive)
  (my-backup-timeline))

(define-key backup-timeline-mode-map (kbd "RET") #'backup-timeline-restore)
(define-key backup-timeline-mode-map (kbd "<down>") (lambda () (interactive) (forward-line 1) (backup-timeline-preview)))
(define-key backup-timeline-mode-map (kbd "<up>") (lambda () (interactive) (forward-line -1) (backup-timeline-preview)))


;; -------------------------------------------------------------------
;; 6. PACKAGE CONFIGURATION
;; -------------------------------------------------------------------

;; --- Navigation (Vertico/Consult) ---
(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  ;; Fix "Bonkers" file editing by using basic matching for files
  (completion-category-overrides '((file (styles basic partial-completion)))))

(use-package vertico
  :init (vertico-mode 1)
  :custom (vertico-cycle t))

(use-package consult
  :config
  ;; Fix sort order for Note Review (Chronological)
  (setq consult-ripgrep-args
        "rg --null --line-buffered --color=never --max-columns=1000 --path-separator /   --smart-case --no-heading --with-filename --line-number --search-zip --sort path"))

(use-package embark
  :init (setq prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult
  :hook (embark-collect-mode . consult-preview-at-point-mode))

(use-package marginalia :init (marginalia-mode 1))

(use-package dirvish
  :init (dirvish-override-dired-mode)
  :config (setq dired-listing-switches "-agho --group-directories-first")
  :bind (:map dirvish-mode-map ("TAB" . dirvish-subtree-toggle)))

(use-package projectile :init (projectile-mode 1))

;; --- Editing & Git ---
(use-package vundo :config (setq vundo-glyph-alist vundo-unicode-symbols))
(use-package smartparens :hook (prog-mode . smartparens-mode))
(use-package yasnippet :init (yas-global-mode 1))
(use-package yasnippet-snippets)
(use-package wgrep)
(use-package magit)
(use-package diff-hl :hook (prog-mode . diff-hl-mode))
(use-package vterm :when (not (eq system-type 'windows-nt)))

;; --- Languages (LSP) ---
(use-package lsp-mode
  :commands (lsp lsp-deferred)
  :custom
  (lsp-completion-provider :none)
  (lsp-enable-on-type-formatting nil)) ;; Disable aggressive auto-format

(use-package lsp-ui :commands lsp-ui-mode)
(use-package flycheck :init (global-flycheck-mode 1))
(use-package corfu :init (global-corfu-mode 1) :custom (corfu-auto t))

;; Markdown
(use-package markdown-mode
  :mode ("\\.md\\'" . markdown-mode)
  :hook (markdown-mode . lsp-deferred))

;; Go
(use-package go-mode
  :mode "\\.go\\'"
  :hook ((go-mode . lsp-deferred)
         (go-mode . (lambda () (add-hook 'before-save-hook #'pb/go-format-buffer nil t)))))
(defun pb/go-format-buffer ()
  (interactive)
  (when (eq major-mode 'go-mode)
    (cond ((executable-find "goimports") (pb/format-buffer-safely "goimports" nil))
          ((executable-find "gofmt") (pb/format-buffer-safely "gofmt" nil)))))

;; Misc Languages
(use-package json-mode :hook (json-mode . lsp-deferred))
(use-package yaml-mode :hook (yaml-mode . lsp-deferred))
(use-package rust-mode :hook (rust-mode . lsp))
(use-package dockerfile-mode :mode "\\.docker\\'")

(defun my/find-obsidian-vault-root (start-path)
  "Walk up the directory tree to find the folder containing '.obsidian'."
  (let ((current-dir (file-name-directory start-path)))
    (while (and current-dir
                (not (file-exists-p (concat current-dir ".obsidian")))
                (not (equal current-dir "/")))
      (setq current-dir (file-name-directory (directory-file-name current-dir))))
    (if (equal current-dir "/") nil current-dir)))

(defun my/open-in-obsidian ()
  "Open the current Markdown buffer in Obsidian."
  (interactive)
  (unless buffer-file-name
    (user-error "Buffer is not visiting a file"))
  
  (let* ((file-path (expand-file-name buffer-file-name))
         (vault-root (my/find-obsidian-vault-root file-path)))
    
    (unless vault-root
      (user-error "Current file is not inside an Obsidian Vault (no .obsidian folder found)."))
    
    (let* ((vault-name (file-name-nondirectory (directory-file-name vault-root)))
           ;; Calculate path relative to the vault root
           (rel-path (file-relative-name file-path vault-root))
           ;; Construct the URI: obsidian://open?vault=NAME&file=PATH
           (uri (format "obsidian://open?vault=%s&file=%s"
                        (url-hexify-string vault-name)
                        (url-hexify-string rel-path))))
      
      (message "Opening in Obsidian: %s..." rel-path)
      ;; On macOS, browse-url calls 'open', which handles custom URI schemes correctly
      (browse-url uri))))

;; Bind it to a key (e.g., C-c o)
(global-set-key (kbd "C-c o") 'my/open-in-obsidian)

;; -------------------------------------------------------------------
;; 7. GLOBAL KEYBINDINGS (The Grand Scheme)
;; -------------------------------------------------------------------

;; --- A. Navigation & Search ---
(global-set-key (kbd "C-s")     #'isearch-forward)      ; Standard "Flashlight" Search
(global-set-key (kbd "C-r")     #'isearch-backward)     ; Reverse "Flashlight" Search
(global-set-key (kbd "M-s l")   'consult-line)          ; Search current buffer (List view)
(global-set-key (kbd "M-s r")   'consult-ripgrep)       ; Search Project (Grep)
(global-set-key (kbd "C-c r")   'consult-ripgrep)       ; Search Project (Review Workflow)
(global-set-key (kbd "C-c f")   'consult-fd)            ; Find File (Fast)
(global-set-key (kbd "C-x b")   'consult-buffer)        ; Switch Buffer (Enhanced)
(global-set-key (kbd "M-g g")   'consult-goto-line)     ; Go to Line (Live Preview)
(global-set-key (kbd "M-y")     'consult-yank-pop)      ; Clipboard History

;; --- B. Embark (The "Right Click") ---
(global-set-key (kbd "C-.")     'embark-act)            ; Action Menu (Export, etc)
(global-set-key (kbd "C-;")     'embark-dwim)           ; Do What I Mean

;; --- C. Review Workflow (F-Keys) ---
(global-set-key (kbd "<f5>")    'previous-error)          ; Back (Previous Note)
(global-set-key (kbd "<f6>")    'next-error)              ; Next (Next Note)
(global-set-key (kbd "<f7>")    'my/delete-note-and-next) ; TRASH note & Auto-Next
(global-set-key (kbd "<f8>")    'compile)                 ; Compile

;; --- D. AI Tools ---
(global-set-key (kbd "C-c q")   'ai-new-prompt)               ; New Prompt Buffer
(global-set-key (kbd "C-c s")   'ai-append-diff-and-copy)     ; Save Prompt & Diff
(global-set-key (kbd "C-c P")   'ai-apply-patch-from-clipboard) ; Apply Patch
(global-set-key (kbd "C-c g")   'pb/send-prompt-to-brave)     ; Send to Gemini
;; ** NEW **
(global-set-key (kbd "C-c TAB") 'ai-demo-ghost-text)          ; Show Fake Ghost Text

;; --- E. Editing & Buffer Management ---
(global-set-key (kbd "M-w")     'pb/copy-region-and-sync)     ; Smart Copy (to System)
(global-set-key (kbd "C-c k")   'kill-to-end-of-buffer)       ; Kill rest of buffer
(global-set-key (kbd "C-c a")   'copy-whole-buffer)           ; Copy all
(global-set-key (kbd "C-x u")   'vundo)                       ; Undo Tree
(global-set-key (kbd "C-:")     'avy-goto-char)               ; Teleport to Char
(global-set-key (kbd "C-'")     'avy-goto-line)               ; Teleport to Line (Visible)

;; --- F. System & Git ---
(global-set-key (kbd "C-c m")   'pb/reset-mouse)              ; Reset Mouse
(global-set-key (kbd "C-x g")   'magit-status)                ; Git Status
(global-set-key (kbd "C-c t")   'my-backup-timeline)          ; Time Travel Backups
(global-set-key (kbd "C-c b")   'my-backup-restore)           ; Restore Backups

;; --- G. Cleanup ---
(global-set-key (kbd "C-x C-c") 'kill-emacs)
(defun my/disable-process-query ()
  (dolist (proc (process-list)) (set-process-query-on-exit-flag proc nil)))
(add-hook 'kill-emacs-hook #'my/disable-process-query)

(custom-set-faces
 ;; 1. The "Lazy" Matches (All other matches on screen) - Dark Blue + White Text
 '(lazy-highlight ((t (:background "#0000aa" :foreground "white" :weight bold))))
 ;; 2. The "Current" Match (The one you are on) - Dark Magenta + White Text
 '(isearch ((t (:background "#aa00aa" :foreground "white" :weight bold))))
 ;; 3. Consult Preview (Linking it to isearch logic)
 '(consult-preview-match ((t (:inherit isearch)))))

(provide 'init)
;;; init.el ends here
