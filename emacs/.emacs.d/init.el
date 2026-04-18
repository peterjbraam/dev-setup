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

;; Modern convenience: typing replaces active region, C-w kills safely
(delete-selection-mode 1)

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
;; 4. CLIPBOARD LOGIC (Strict OS/Emacs Isolation)
;; -------------------------------------------------------------------

;; Keep the GUI visuals, but remove GUI clipboard checks
(when (display-graphic-p)
  (set-cursor-color "#FF8C00") 
  (tab-bar-mode 1)
  (setq tab-bar-show 1)          
  (setq tab-bar-new-tab-choice "*scratch*"))

(use-package clipetty :ensure t :demand t)

;; 1. C-w ONLY goes to Emacs internal kill-ring (No OS sync)
(setq interprogram-cut-function nil)

;; 2. C-y ONLY pulls from Emacs internal kill-ring (No OS sync)
(setq interprogram-paste-function nil)

;; 3. Explicit Copy to OS System (M-w only)
(defun pb/copy-region-and-sync (beg end)
  "Copy region to kill-ring AND sync to system clipboard."
  (interactive "r")
  ;; A. Internal Emacs Copy
  (cond
   ((and (minibufferp) (not (use-region-p)))
    (kill-new (minibuffer-contents)))
   (t
    (kill-ring-save beg end)))
  
  ;; B. System Sync (The M-w bridge)
  (cond
   ((fboundp 'clipetty-copy)
    (clipetty-copy (car kill-ring))
    (message "Copied to System (via Clipetty)."))
   ((executable-find "pbcopy")
    (let ((process-connection-type nil))
      (let ((proc (start-process "pbcopy" nil "pbcopy")))
        (process-send-string proc (car kill-ring))
        (process-send-eof proc)))
    (message "Copied to System (via pbcopy)."))
   (t
    (message "Copied to Ring (System clipboard unavailable)."))))

;; -------------------------------------------------------------------
;; 5. CUSTOM FUNCTIONS (Tools & Workflows)
;; -------------------------------------------------------------------

(defun kill-to-end-of-buffer ()
  (interactive)
  (kill-region (point) (point-max)))

(defun copy-whole-buffer ()
  "Copy entire buffer to OS system clipboard."
  (interactive)
  (pb/copy-region-and-sync (point-min) (point-max))
  (message "Entire buffer copied to system clipboard!"))

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

;; -------------------------------------------------------------------
;; 6. GGO IPC INTEGRATION (The AI Chat Terminal)
;; -------------------------------------------------------------------
(require 'ansi-color)

(defun ggo--get-active-project ()
  (let ((config-file (expand-file-name "~/.ggo/config.yaml")))
    (if (file-exists-p config-file)
        (with-temp-buffer
          (insert-file-contents config-file)
          (goto-char (point-min))
          (if (re-search-forward "^last_project:[ \t]*\\(.*?\\)$" nil t)
              (match-string 1)
            (error "No last_project found in ggo config.")))
      (error "ggo config not found."))))

(defun ggo--get-pipe (pipe-name)
  (let ((proj (ggo--get-active-project)))
    (expand-file-name (format "~/.ggo/ggoai-%s/run/%s" proj pipe-name))))

(defvar-local ggo-response-process nil)
(defvar-local ggo-prompt-counter 1)

(defun ggo-start-listener ()
  (interactive)
  (let* ((pipe (ggo--get-pipe "response.pipe"))
         (buf (current-buffer))
         ;; MAGIC FIX: Force pty to prevent tail output buffering!
         (process-connection-type t)) 
    (unless (file-exists-p pipe)
      (user-error "ggo daemon is not running!"))
    
    (when (process-live-p ggo-response-process)
      (set-process-query-on-exit-flag ggo-response-process nil)
      (delete-process ggo-response-process))
    
    (setq ggo-response-process
          (make-process
           :name "ggo-response-listener"
           :buffer buf
           :command (list "tail" "-f" pipe)
           :sentinel (lambda (proc event) nil) 
           :filter (lambda (proc string)
                     (when (buffer-live-p (process-buffer proc))
                       (with-current-buffer (process-buffer proc)
                         (let ((moving (= (point) (point-max)))
                               ;; Process daemon ANSI colors
                               (clean-str (ansi-color-apply string)))
                           (save-excursion
                             (goto-char (point-max))
                             (insert clean-str))
                           (when moving (goto-char (point-max)))))))))))

(defun ggo-insert-prompt ()
  "Insert a bash-like prompt at the bottom of the buffer."
  (interactive)
  (goto-char (point-max))
  (unless (bolp) (insert "\n"))
  (let* ((proj (ggo--get-active-project))
         (ts (format-time-string "%H:%M:%S"))
         ;; Use markdown bold so it looks clean: **proj:10:45 [1]>**
         (prompt-str (format "\n**%s:%s [%d]>** " proj ts ggo-prompt-counter)))
    (insert prompt-str)
    (setq ggo-prompt-counter (1+ ggo-prompt-counter))))

(defun ggo-get-current-prompt-text ()
  (save-excursion
    (let ((end (point-max)))
      ;; Search backwards for the prompt marker
      (if (re-search-backward "\\*\\*.*?>\\*\\*[ \t]*" nil t)
          (progn
            (goto-char (match-end 0))
            (string-trim (buffer-substring-no-properties (point) end)))
        ""))))

(defun ggo-send-prompt ()
  (interactive)
  (let ((input-text (ggo-get-current-prompt-text)))
    (if (string-empty-p input-text)
        (message "Input is empty!")
      
      (goto-char (point-max))
      (insert "\n") ;; Let the daemon provide the response formatting
      
      (if (string-prefix-p "/" input-text)
          (let ((cmd-string (substring input-text 1))
                (pipe (ggo--get-pipe "control.pipe")))
            (write-region (concat cmd-string "\n") nil pipe 'append)
            (message "Command sent."))
        
        (let ((pipe (ggo--get-pipe "prompt.pipe")))
          (write-region (concat input-text "\n") nil pipe 'append)
          (message "Prompt sent."))))))

(defun ggo-control-send (cmd-string)
  (let ((pipe (ggo--get-pipe "control.pipe")))
    (write-region (concat cmd-string "\n") nil pipe 'append)))

(defun ggo-write-files () (interactive) (ggo-control-send "WF"))

(defun ggo-abort-and-prompt ()
  "Send ABORT signal to daemon and instantly drop a new prompt."
  (interactive)
  (ggo-control-send "ABORT")
  (ggo-insert-prompt))

(define-derived-mode ggo-chat-mode markdown-mode "ggo-chat"
  (ggo-start-listener)
  (add-hook 'kill-buffer-hook 
            (lambda ()
              (when (process-live-p ggo-response-process)
                (delete-process ggo-response-process)))
            nil t))

(define-key ggo-chat-mode-map (kbd "C-c C-c") 'ggo-send-prompt)
(define-key ggo-chat-mode-map (kbd "C-c C-w") 'ggo-write-files)
(define-key ggo-chat-mode-map (kbd "C-c C-k") 'ggo-abort-and-prompt)
(define-key ggo-chat-mode-map (kbd "RET")
  (lambda () 
    (interactive) 
    (if (and (= (point) (point-max)) (not (string-empty-p (ggo-get-current-prompt-text))))
        (ggo-send-prompt)
      (newline))))

(defun ggo-new-chat ()
  (interactive)
  (let* ((proj (ggo--get-active-project))
         (chat-file (expand-file-name (format "~/.ggo/ggoai-%s/current-chat.md" proj))))
    ;; Just open the file normally. Emacs will auto-detect Markdown mode.
    (find-file chat-file)
    (unless (eq major-mode 'ggo-chat-mode)
      (ggo-chat-mode))
    (when (= (buffer-size) 0)
      (let ((ts (format-time-string "%Y-%m-%d %H:%M:%S")))
        (insert (format "# ggo Chat\n*Project: %s*\n*Started: %s*\n\n---\n" proj ts))))
    ;; Only insert a prompt if we are at the bottom of the file
    (when (= (point) (point-max))
      (ggo-insert-prompt))
    (message "Type a prompt or /command, then press C-c C-c (or Return at end of line).")))

(defun ggo-jump-to-chat ()
  (interactive)
  (let* ((has-region (use-region-p))
         (selected-text (when has-region (buffer-substring-no-properties (region-beginning) (region-end))))
         (filename (when buffer-file-name (file-name-nondirectory buffer-file-name))))
    
    (if has-region
        (progn
          (setq ggo--target-beg (set-marker (make-marker) (region-beginning)))
          (setq ggo--target-end (set-marker (make-marker) (region-end)))
          (deactivate-mark))
      (progn
        (setq ggo--target-beg (set-marker (make-marker) (point-min)))
        (setq ggo--target-end (set-marker (make-marker) (point-max)))))
    
    ;; Use the new function to jump safely
    (ggo-new-chat)
    
    (when (and has-region filename)
      (goto-char (point-max))
      (insert (format "\nRegarding `%s`:\n```text\n%s\n```\n" filename selected-text)))
    
    (ggo-insert-prompt)
    (message "Ready to prompt!")))


(defun ggo-ediff-clipboard ()
  (interactive)
  (let* ((clip-text (string-trim (shell-command-to-string "pbpaste")))
         (target-buf (current-buffer))
         (m-beg (if (and (boundp 'ggo--target-beg) (markerp ggo--target-beg))
                    ggo--target-beg
                  (set-marker (make-marker) (if (use-region-p) (region-beginning) (point-min)))))
         (m-end (if (and (boundp 'ggo--target-end) (markerp ggo--target-end))
                    ggo--target-end
                  (set-marker (make-marker) (if (use-region-p) (region-end) (point-max)))))
         (orig-text (buffer-substring-no-properties m-beg m-end))
         (orig-buf (generate-new-buffer "*ggo-original*"))
         (clip-buf (generate-new-buffer "*ggo-clipboard*")))
    
    (if (string-empty-p clip-text)
        (user-error "Clipboard is empty! Did the LLM output a code block?")
      (with-current-buffer orig-buf
        (insert orig-text)
        (funcall (buffer-local-value 'major-mode target-buf)))
      (with-current-buffer clip-buf
        (insert clip-text)
        (funcall (buffer-local-value 'major-mode target-buf)))
      (when (use-region-p) (deactivate-mark))
      (ediff-buffers orig-buf clip-buf
                     `((lambda ()
                         (add-hook 'ediff-quit-hook
                                   (lambda ()
                                     (let ((final-text (with-current-buffer ,orig-buf (buffer-string))))
                                       (with-current-buffer ,target-buf
                                         (delete-region ,m-beg ,m-end)
                                         (save-excursion
                                            (goto-char ,m-beg)
                                            (insert final-text)))
                                       (kill-buffer ,orig-buf)
                                       (kill-buffer ,clip-buf)
                                       (set-marker ,m-beg nil)
                                       (set-marker ,m-end nil)
                                       (message "Snippet merged!")))
                                   nil 'local)))))))


;; -------------------------------------------------------------------
;; 7. REVIEW & BACKUP WORKFLOWS
;; -------------------------------------------------------------------

(defun my/delete-note-and-next ()
  "INSTANTLY trash current file, kill buffer, and jump to next result."
  (interactive)
  (let ((filename (buffer-file-name))
        (current-buf (current-buffer)))
    (if (not filename)
        (message "Buffer is not visiting a file!")
      (move-file-to-trash filename)
      (message "Trashed: %s" (file-name-nondirectory filename))
      (condition-case nil
          (next-error)
        (error (message "End of list!")))
      (kill-buffer current-buf))))

(global-auto-revert-mode 1)
(setq global-auto-revert-non-file-buffers t)
(auto-save-visited-mode 1)
(setq auto-save-visited-interval 1)
(setq make-backup-files nil create-lockfiles nil)


;; -------------------------------------------------------------------
;; 7b . TIME MACHINE & BACKUP WORKFLOWS
;; -------------------------------------------------------------------

(defvar my-time-machine-dir (expand-file-name "~/.emacs.d/timebackups/"))

;; Background Saver (Unchanged)
(defun my-smart-backup ()
  (when (and buffer-file-name (file-writable-p buffer-file-name))
    (let ((min (string-to-number (format-time-string "%M"))))
      (when (zerop (% min 2))
        (make-directory my-time-machine-dir t)
        (let* ((file (file-name-nondirectory buffer-file-name))
               (stamp (format-time-string "%Y-%m-%d-%H:%M:%S"))
               (target (expand-file-name (format "%s.%s" file stamp) my-time-machine-dir)))
          (copy-file buffer-file-name target t))))))

(run-with-timer 10 60 (lambda () (save-excursion (dolist (buf (buffer-list)) (with-current-buffer buf (when (buffer-file-name) (my-smart-backup)))))))

;; --- The Time Machine Engine ---

(defun tm--relative-time (mtime)
  "Convert modification time to a readable relative string (-5m, -2h)."
  (let* ((diff (float-time (time-subtract (current-time) mtime)))
         (mins (round (/ diff 60.0))))
    (cond
     ((< mins 60) (format "-%dm" mins))
     ((< mins 1440) (format "-%dh" (round (/ mins 60.0))))
     (t (format "-%dd" (round (/ mins 1440.0)))))))

(define-derived-mode time-machine-mode special-mode "TimeMachine"
  "Major mode for navigating backup timelines, mirroring vundo UX."
  (setq truncate-lines t)
  (setq cursor-type 'box))

;; State Variables
(defvar-local tm--target-file nil)
(defvar-local tm--target-buf nil)
(defvar-local tm--diff-buf nil)
(defvar-local tm--auto-save-state nil)

(defun tm-quit ()
  "Quit the time machine, clean up diffs, and restore auto-save."
  (interactive)
  (when tm--auto-save-state
    (with-current-buffer tm--target-buf
      (auto-save-visited-mode 1)
      (message "Time Machine closed. Auto-save resumed.")))
  (when (buffer-live-p tm--diff-buf) (kill-buffer tm--diff-buf))
  (kill-buffer (current-buffer)))

(defun tm--get-current-backup-file ()
  "Extract the backup filename from the current line."
  (let ((line (thing-at-point 'line t)))
    (if (and line (string-match "^\\(.*?\\) \\(" line))
        (expand-file-name (match-string 1 line) my-time-machine-dir)
      nil)))

(defun tm-show-diff ()
  "Show unified diff for the current line's backup."
  (interactive)
  (let ((backup (tm--get-current-backup-file)))
    (when (and backup (file-exists-p backup))
      (when (buffer-live-p tm--diff-buf) (kill-buffer tm--diff-buf))
      (setq tm--diff-buf (get-buffer-create "*Time Machine Diff*"))
      (with-current-buffer tm--diff-buf
        (erase-buffer)
        (insert (shell-command-to-string (format "diff -u %s %s" backup tm--target-file)))
        (diff-mode))
      (display-buffer tm--diff-buf '((display-buffer-at-bottom))))))

(defun tm-ediff ()
  "Launch Ediff for the selected backup."
  (interactive)
  (let ((backup (tm--get-current-backup-file))
        (orig-buf tm--target-buf)
        (auto-state tm--auto-save-state)
        (tm-buf (current-buffer)))
    (when (and backup (file-exists-p backup))
      (when (buffer-live-p tm--diff-buf) (kill-buffer tm--diff-buf))
      ;; Ediff order: Backup is 'A', Current is 'B'. 
      ;; Pressing 'a' in Ediff pulls the old code into the present.
      (ediff-files backup tm--target-file)
      ;; Clean up when Ediff finishes
      (add-hook 'ediff-quit-hook
                `(lambda ()
                   (when ,auto-state
                     (with-current-buffer ,orig-buf
                       (auto-save-visited-mode 1)
                       (message "Ediff merged. Auto-save resumed.")))
                   (when (buffer-live-p ,tm-buf) (kill-buffer ,tm-buf)))
                nil t))))

;; The UX Keybindings (Identical to Vundo logic)
(define-key time-machine-mode-map (kbd "n") 'next-line)
(define-key time-machine-mode-map (kbd "p") 'previous-line)
(define-key time-machine-mode-map (kbd "d") 'tm-show-diff)
(define-key time-machine-mode-map (kbd "RET") 'tm-ediff)
(define-key time-machine-mode-map (kbd "q") 'tm-quit)

(defun my-time-machine ()
  "Launch the disk-based Time Machine for the current buffer."
  (interactive)
  (unless buffer-file-name (user-error "Not visiting a file!"))
  (let* ((target buffer-file-name)
         (buf (current-buffer))
         (filename (file-name-nondirectory target))
         (auto-save-was-on (bound-and-true-p auto-save-visited-mode))
         (backups (sort (directory-files my-time-machine-dir t (concat "^" (regexp-quote filename) "\\.")) #'string>))
         (tm-buf (get-buffer-create "*Time Machine*")))
    
    (unless backups (user-error "No backups found for %s" filename))
    
    ;; 1. PAUSE TIME: Stop auto-save immediately.
    (when auto-save-was-on
      (auto-save-visited-mode -1)
      (message "Time Machine active. Auto-save paused."))

    ;; 2. BUILD THE UI
    (with-current-buffer tm-buf
      (setq buffer-read-only nil)
      (erase-buffer)
      (setq-local tm--target-file target)
      (setq-local tm--target-buf buf)
      (setq-local tm--auto-save-state auto-save-was-on)
      
      (insert (format "=== TIME MACHINE: %s ===\n" filename))
      (insert "[n/p] Navigate | [d] Live Diff | [RET] Extract via Ediff | [q] Quit\n\n")
      
      (dolist (f backups)
        (let* ((attrs (file-attributes f))
               (mtime (file-attribute-modification-time attrs)))
          (insert (format "%s  (%s)\n" (file-name-nondirectory f) (tm--relative-time mtime)))))
      
      (time-machine-mode)
      (goto-char (point-min))
      (forward-line 3)) ;; Jump to first backup
    (pop-to-buffer tm-buf)))

(global-set-key (kbd "C-c t") 'my-time-machine)

;; -------------------------------------------------------------------
;; 8. PACKAGE CONFIGURATION
;; -------------------------------------------------------------------

(add-hook 'makefile-mode-hook (lambda () (setq indent-tabs-mode t)))
(add-hook 'makefile-bsdmake-mode-hook (lambda () (setq indent-tabs-mode t)))

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles basic partial-completion)))))

(use-package vertico 
  :init (vertico-mode 1) 
  :custom (vertico-cycle t)
)

(add-to-list 'completion-ignored-extensions ".DS_Store")
(use-package consult
  :config
  (setq consult-ripgrep-args "rg --null --line-buffered --color=never --max-columns=1000 --path-separator /   --smart-case --no-heading --with-filename --line-number --search-zip --sort path"))

(use-package embark :init (setq prefix-help-command #'embark-prefix-help-command))
(use-package embark-consult :hook (embark-collect-mode . consult-preview-at-point-mode))
(use-package marginalia :init (marginalia-mode 1))

(use-package dirvish
  :init (dirvish-override-dired-mode)
  :config (setq dired-listing-switches "-agho --group-directories-first")
  :bind (:map dirvish-mode-map ("TAB" . dirvish-subtree-toggle)))

(use-package projectile :init (projectile-mode 1))

(use-package vundo :config (setq vundo-glyph-alist vundo-unicode-symbols))
(use-package smartparens :hook (prog-mode . smartparens-mode))
(use-package yasnippet :init (yas-global-mode 1))
(use-package yasnippet-snippets)
(use-package wgrep)
(use-package magit)
(use-package diff-hl :hook (prog-mode . diff-hl-mode))
(use-package vterm :when (not (eq system-type 'windows-nt)))

(use-package lsp-mode
  :commands (lsp lsp-deferred)
  :custom
  (lsp-completion-provider :none)
  (lsp-enable-on-type-formatting nil))

(use-package lsp-ui :commands lsp-ui-mode)
(use-package flycheck :init (global-flycheck-mode 1))
(use-package corfu :init (global-corfu-mode 1) :custom (corfu-auto t))

(use-package markdown-mode
  :mode ("\\.md\\'" . markdown-mode)
  :hook (markdown-mode . (lambda ()
                           (setq-local corfu-auto nil)
                           (flyspell-mode 1)
                           (visual-line-mode 1)))) ;; <-- The modern soft-wrap magic


(use-package go-mode
  :mode "\\.go\\'"
  :hook ((go-mode . lsp-deferred)
         (go-mode . (lambda () (add-hook 'before-save-hook #'pb/go-format-buffer nil t)))))

(defun pb/go-format-buffer ()
  (interactive)
  (when (eq major-mode 'go-mode)
    (cond ((executable-find "goimports") (pb/format-buffer-safely "goimports" nil))
          ((executable-find "gofmt") (pb/format-buffer-safely "gofmt" nil)))))

(use-package json-mode :hook (json-mode . lsp-deferred))
(use-package yaml-mode :hook (yaml-mode . lsp-deferred))
(use-package rust-mode :hook (rust-mode . lsp))
(use-package dockerfile-mode :mode "\\.docker\\'")

(defun my/find-obsidian-vault-root (start-path)
  (let ((current-dir (file-name-directory start-path)))
    (while (and current-dir
                (not (file-exists-p (concat current-dir ".obsidian")))
                (not (equal current-dir "/")))
      (setq current-dir (file-name-directory (directory-file-name current-dir))))
    (if (equal current-dir "/") nil current-dir)))

(defun my/open-in-obsidian ()
  (interactive)
  (unless buffer-file-name (user-error "Buffer is not visiting a file"))
  (let* ((file-path (expand-file-name buffer-file-name))
         (vault-root (my/find-obsidian-vault-root file-path)))
    (unless vault-root (user-error "Current file is not inside an Obsidian Vault."))
    (let* ((vault-name (file-name-nondirectory (directory-file-name vault-root)))
           (rel-path (file-relative-name file-path vault-root))
           (uri (format "obsidian://open?vault=%s&file=%s"
                        (url-hexify-string vault-name)
                        (url-hexify-string rel-path))))
      (message "Opening in Obsidian: %s..." rel-path)
      (browse-url uri))))

(global-set-key (kbd "C-c o") 'my/open-in-obsidian)

;; -------------------------------------------------------------------
;; 9. GLOBAL KEYBINDINGS
;; -------------------------------------------------------------------

(global-set-key (kbd "C-s")     #'isearch-forward)
(global-set-key (kbd "C-r")     #'isearch-backward)
(global-set-key (kbd "M-s l")   'consult-line)
(global-set-key (kbd "M-s r")   'consult-ripgrep)
(global-set-key (kbd "C-c r")   'consult-ripgrep)
(global-set-key (kbd "C-c f")   'consult-fd)
(global-set-key (kbd "C-x b")   'consult-buffer)
(global-set-key (kbd "M-g g")   'consult-goto-line)
(global-set-key (kbd "M-y")     'consult-yank-pop)

(global-set-key (kbd "C-.")     'embark-act)
(global-set-key (kbd "C-;")     'embark-dwim)

(global-set-key (kbd "<f5>")    'previous-error)
(global-set-key (kbd "<f6>")    'next-error)
(global-set-key (kbd "<f7>")    'my/delete-note-and-next)
(global-set-key (kbd "<f8>")    'compile)

;; ggo bindings
(global-set-key (kbd "C-c c") 'ggo-jump-to-chat)
(global-set-key (kbd "C-c e") 'ggo-ediff-clipboard)

(global-set-key (kbd "M-w")     'pb/copy-region-and-sync)
(global-set-key (kbd "C-c k")   'kill-to-end-of-buffer)
(global-set-key (kbd "C-c a")   'copy-whole-buffer)
(global-set-key (kbd "C-x u")   'vundo)
(global-set-key (kbd "C-:")     'avy-goto-char)
(global-set-key (kbd "C-'")     'avy-goto-line)

(global-set-key (kbd "C-c m")   'pb/reset-mouse)
(global-set-key (kbd "C-x g")   'magit-status)
(global-set-key (kbd "C-c t")   'my-backup-timeline)
(global-set-key (kbd "C-c b")   'my-backup-restore)

(global-set-key (kbd "C-x C-c") 'kill-emacs)
(defun my/disable-process-query ()
  (dolist (proc (process-list)) (set-process-query-on-exit-flag proc nil)))
(add-hook 'kill-emacs-hook #'my/disable-process-query)

(custom-set-faces
 '(consult-preview-match ((t (:inherit isearch))))
 '(isearch ((t (:background "#aa00aa" :foreground "white" :weight bold))))
 '(lazy-highlight ((t (:background "#0000aa" :foreground "white" :weight bold)))))
(set-face-attribute 'region nil :background "#FFE4B5" :foreground "#000000")


(provide 'init)
(custom-set-variables
 '(package-selected-packages
   '(which-key yasnippet-snippets yaml-mode wgrep vundo vterm vertico swift-mode smartparens rust-mode rpm-spec-mode projectile orderless marginalia magit lsp-ui kind-icon json-mode helm-rg helm-ls-git go-mode flycheck embark-consult dockerfile-mode dirvish diff-hl debian-el corfu clipetty bazel avy)))
;;; init.el ends here
