,;; Init.el --- portable, devcontainer Emacs config  -*- lexical-binding: t; -*-
;; Commentary
;; -------------------------------------------------------------------
;; 1. CRITICAL COMPATIBILITY FIXES (Must run first)
;; -------------------------------------------------------------------

(unless (fboundp 'x-hide-tip)
  (defalias 'x-hide-tip #'ignore))

;; -------------------------------------------------------------------
;; 2. PACKAGE BOOTSTRAP
;; -------------------------------------------------------------------

(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))

;; (package-initialize) ;; not needed after emacs 27
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

(delete-selection-mode 1)

;; Bracketed Paste Garbage Fix
(require 'term/xterm)
(global-set-key "\e[200~" 'xterm-paste)
(eval-after-load "term/xterm"
  '(if (listp xterm-extra-capabilities)
       (setq xterm-extra-capabilities (remove 'bracketedPaste xterm-extra-capabilities))
     (setq xterm-extra-capabilities '(modifyOtherKeys setSelection))))

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

(when (display-graphic-p)
  (set-cursor-color "#FF8C00") 
  (tab-bar-mode 1)
  (setq tab-bar-show 1)          
  (setq tab-bar-new-tab-choice "*scratch*"))

(use-package clipetty :ensure t :demand t)

(setq interprogram-cut-function nil)
(setq interprogram-paste-function nil)

(defun pb/copy-region-and-sync ()
  "Copy region to kill-ring AND sync to system clipboard safely."
  (interactive)
  (let ((text (cond
               ((use-region-p) (buffer-substring-no-properties (region-beginning) (region-end)))
               ((minibufferp) (minibuffer-contents))
               (t nil))))
    (if (not text)
        (message "No region active; nothing copied.")
      (kill-new text)
      (deactivate-mark)
      (cond
       ((fboundp 'clipetty-copy)
        (clipetty-copy text)
        (message "Copied to System (via Clipetty)."))
       ((executable-find "pbcopy")
        (let ((process-connection-type nil))
          (let ((proc (start-process "pbcopy" nil "pbcopy")))
            (process-send-string proc text)
            (process-send-eof proc)))
        (message "Copied to System (via pbcopy)."))
       (t
        (message "Copied to Ring (System clipboard unavailable)."))))))

;; -------------------------------------------------------------------
;; 5. CUSTOM FUNCTIONS (Tools & Workflows)
;; -------------------------------------------------------------------

(defun kill-to-end-of-buffer ()
  (interactive)
  (kill-region (point) (point-max)))

(defun copy-whole-buffer ()
  "Copy entire buffer to OS system clipboard."
  (interactive)
  (mark-whole-buffer)
  (pb/copy-region-and-sync)
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
(add-to-list 'load-path "/Users/braam/sw/ggo/plugins")
;; Note: Ensure 'ggo package is available or installed
(require 'ggo nil t) 

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

(defun tm--relative-time (mtime)
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

(defvar-local tm--target-file nil)
(defvar-local tm--target-buf nil)
(defvar-local tm--diff-buf nil)
(defvar-local tm--auto-save-state nil)

(defun tm-quit ()
  (interactive)
  (when tm--auto-save-state
    (with-current-buffer tm--target-buf
      (auto-save-visited-mode 1)
      (message "Time Machine closed. Auto-save resumed.")))
  (when (buffer-live-p tm--diff-buf) (kill-buffer tm--diff-buf))
  (kill-buffer (current-buffer)))

(defun tm--get-current-backup-file ()
  (let ((line (thing-at-point 'line t)))
    (if (and line (string-match "^\\(.*?\\) \\(" line))
        (expand-file-name (match-string 1 line) my-time-machine-dir)
      nil)))

(defun tm-show-diff ()
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
  (interactive)
  (let ((backup (tm--get-current-backup-file))
        (orig-buf tm--target-buf)
        (auto-state tm--auto-save-state)
        (tm-buf (current-buffer)))
    (when (and backup (file-exists-p backup))
      (when (buffer-live-p tm--diff-buf) (kill-buffer tm--diff-buf))
      (ediff-files backup tm--target-file)
      (add-hook 'ediff-quit-hook
                `(lambda ()
                   (when ,auto-state
                     (with-current-buffer ,orig-buf
                       (auto-save-visited-mode 1)
                       (message "Ediff merged. Auto-save resumed.")))
                   (when (buffer-live-p ,tm-buf) (kill-buffer ,tm-buf)))
                nil t))))

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
    (when auto-save-was-on
      (auto-save-visited-mode -1)
      (message "Time Machine active. Auto-save paused."))
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
      (forward-line 3))
    (pop-to-buffer tm-buf)))

;; -------------------------------------------------------------------
;; 8. PACKAGE CONFIGURATION (Modular Bindings)
;; -------------------------------------------------------------------

(add-hook 'makefile-mode-hook (lambda () (setq indent-tabs-mode t)))
(add-hook 'makefile-bsdmake-mode-hook (lambda () (setq indent-tabs-mode t)))

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles orderless partial-completion)))))

(require 'recentf)
(setq recentf-max-saved-items 2000)
(setq recentf-auto-cleanup 'never)
(recentf-mode 1)

(use-package vertico 
  :init (vertico-mode 1) 
  :custom (vertico-cycle t))

(add-to-list 'completion-ignored-extensions ".DS_Store")

(use-package consult
  :bind (("M-s l" . consult-line)
         ("M-s r" . consult-ripgrep)
         ("C-c r" . consult-ripgrep)
         ("C-c f" . consult-fd)
         ("C-x b" . consult-buffer)
         ("M-g g" . consult-goto-line)
         ("M-y"   . consult-yank-pop))
  :config
  (setq consult-ripgrep-args "rg --null --line-buffered --color=never --max-columns=1000 --path-separator /   --smart-case --no-heading --with-filename --line-number --search-zip --sort path"))

(use-package embark 
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim))
  :init (setq prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult :hook (embark-collect-mode . consult-preview-at-point-mode))
(use-package marginalia :init (marginalia-mode 1))

(use-package dirvish
  :init (dirvish-override-dired-mode)
  :config (setq dired-listing-switches "-agho --group-directories-first")
  :bind (:map dirvish-mode-map ("TAB" . dirvish-subtree-toggle)))

(use-package projectile :init (projectile-mode 1))
(use-package vundo 
  :bind ("C-x u" . vundo)
  :config (setq vundo-glyph-alist vundo-unicode-symbols))

(use-package avy
  :bind (("C-:" . avy-goto-char)
         ("C-'" . avy-goto-line)))

(use-package magit
  :bind ("C-x g" . magit-status))

(use-package smartparens :hook (prog-mode . smartparens-mode))
(use-package yasnippet :init (yas-global-mode 1))
(use-package yasnippet-snippets)
(use-package wgrep)
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

;; --- The Markdown Bulletproof Engine ---
(defun pb/region-make-todo-list-and-clean (beg end)
  "Convert headings to checkboxes and clean up double checkboxes."
  (interactive
   (if (use-region-p)
       (list (region-beginning) (region-end))
     (list (line-beginning-position) (line-end-position))))
  (save-excursion
    (save-restriction
      (narrow-to-region beg end)
      (goto-char (point-min))
      (while (re-search-forward "^[ \t]*#+[ \t]+" nil t)
        (replace-match "- [ ] "))
      (goto-char (point-min))
      (while (re-search-forward "- \\[ \\][ \t]*- ?\\[ ?\\][ \t]*" nil t)
        (replace-match "- [ ] ")))))

(defun pb/markdown-complete-task ()
  "Toggle markdown checkbox. If checked, append the current date."
  (interactive)
  (let ((line-text (thing-at-point 'line t)))
    (markdown-toggle-gfm-checkbox)
    (when (string-match-p "- \\[ \\]" line-text)
      (end-of-line)
      (insert (format " @done(%s)" (format-time-string "%Y-%m-%d"))))))

(defun pb/markdown-format-buffer ()
  "Run markdownlint --fix on the current buffer safely."
  (interactive)
  (when (and (eq major-mode 'markdown-mode)
             (executable-find "markdownlint"))
    (pb/format-buffer-safely "markdownlint" '("--fix" "--stdin"))))

(use-package markdown-mode
  :mode ("\\.md\\'" . markdown-mode)
  :bind (:map markdown-mode-map
              ("C-c l"   . pb/region-make-todo-list-and-clean)
              ("C-c C-d" . pb/markdown-complete-task)
              ("M-<right>" . markdown-demote-list-item)
              ("M-<left>"  . markdown-promote-list-item)
              ("M-<up>"    . markdown-move-list-item-up)
              ("M-<down>"  . markdown-move-list-item-down)
              ("TAB"       . markdown-cycle)
              ("<backtab>" . markdown-shifttab))
  :init
  (add-hook 'markdown-mode-hook 
            (lambda ()
              (setq-local corfu-auto nil)
              (flyspell-mode 1)
              (visual-line-mode 1)
              (flycheck-mode -1)
              (add-hook 'before-save-hook #'pb/markdown-format-buffer nil t)))
  :config
  (setq markdown-list-indent-width 4))

;; --- Go Mode ---
(use-package go-mode
  :mode "\\.go\\'"
  :hook (go-mode . lsp-deferred)
  :init
  (add-hook 'go-mode-hook 
            (lambda () 
              (add-hook 'before-save-hook #'pb/go-format-buffer nil t))))

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

;; Init.el --- portable, devcontainer Emacs config  -*- lexical-binding: t; -*-
;; Commentary
;; -------------------------------------------------------------------
;; 1. CRITICAL COMPATIBILITY FIXES (Must run first)
;; -------------------------------------------------------------------

(unless (fboundp 'x-hide-tip)
  (defalias 'x-hide-tip #'ignore))

;; -------------------------------------------------------------------
;; 2. PACKAGE BOOTSTRAP
;; -------------------------------------------------------------------

(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))

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

(delete-selection-mode 1)

;; Bracketed Paste Garbage Fix
(require 'term/xterm)
(global-set-key "\e[200~" 'xterm-paste)
(eval-after-load "term/xterm"
  '(if (listp xterm-extra-capabilities)
       (setq xterm-extra-capabilities (remove 'bracketedPaste xterm-extra-capabilities))
     (setq xterm-extra-capabilities '(modifyOtherKeys setSelection))))

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

(when (display-graphic-p)
  (set-cursor-color "#FF8C00") 
  (tab-bar-mode 1)
  (setq tab-bar-show 1)          
  (setq tab-bar-new-tab-choice "*scratch*"))

(use-package clipetty :ensure t :demand t)

(setq interprogram-cut-function nil)
(setq interprogram-paste-function nil)

(defun pb/copy-region-and-sync ()
  "Copy region to kill-ring AND sync to system clipboard safely."
  (interactive)
  (let ((text (cond
               ((use-region-p) (buffer-substring-no-properties (region-beginning) (region-end)))
               ((minibufferp) (minibuffer-contents))
               (t nil))))
    (if (not text)
        (message "No region active; nothing copied.")
      (kill-new text)
      (deactivate-mark)
      (cond
       ((fboundp 'clipetty-copy)
        (clipetty-copy text)
        (message "Copied to System (via Clipetty)."))
       ((executable-find "pbcopy")
        (let ((process-connection-type nil))
          (let ((proc (start-process "pbcopy" nil "pbcopy")))
            (process-send-string proc text)
            (process-send-eof proc)))
        (message "Copied to System (via pbcopy)."))
       (t
        (message "Copied to Ring (System clipboard unavailable)."))))))

;; -------------------------------------------------------------------
;; 5. CUSTOM FUNCTIONS (Tools & Workflows)
;; -------------------------------------------------------------------

(defun kill-to-end-of-buffer ()
  (interactive)
  (kill-region (point) (point-max)))

(defun copy-whole-buffer ()
  "Copy entire buffer to OS system clipboard."
  (interactive)
  (mark-whole-buffer)
  (pb/copy-region-and-sync)
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
(add-to-list 'load-path "/Users/braam/sw/ggo/plugins")
;; Note: Ensure 'ggo package is available or installed
(require 'ggo nil t) 

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
(setq auto-save-visited-interval 3)

(defvar my-time-machine-dir (expand-file-name "~/.emacs.d/timebackups/"))

(defun my-smart-backup ()
  (when (and buffer-file-name 
             (file-writable-p buffer-file-name))
    (let* ((min (string-to-number (format-time-string "%M")))
           (file-mtime (file-attribute-modification-time (file-attributes buffer-file-name)))
           ;; Only backup if the file was modified within the last 2 minutes (120 seconds)
           (recently-changed (< (float-time (time-subtract (current-time) file-mtime)) 120)))
      (when (and (zerop (% min 2)) recently-changed)
        (make-directory my-time-machine-dir t)
        (let* ((file (file-name-nondirectory buffer-file-name))
               (stamp (format-time-string "%Y-%m-%d-%H:%M:%S"))
               (target (expand-file-name (format "%s.%s" file stamp) my-time-machine-dir)))
          (copy-file buffer-file-name target t))))))


(run-with-timer 10 60 (lambda () (save-excursion (dolist (buf (buffer-list)) (with-current-buffer buf (when (buffer-file-name) (my-smart-backup)))))))

(defun tm--relative-time (mtime)
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

(defvar-local tm--target-file nil)
(defvar-local tm--target-buf nil)
(defvar-local tm--diff-buf nil)
(defvar-local tm--auto-save-state nil)

(defun tm-quit ()
  (interactive)
  (when tm--auto-save-state
    (with-current-buffer tm--target-buf
      (auto-save-visited-mode 1)
      (message "Time Machine closed. Auto-save resumed.")))
  (when (buffer-live-p tm--diff-buf) (kill-buffer tm--diff-buf))
  (kill-buffer (current-buffer)))

(defun tm--get-current-backup-file ()
  (let ((line (thing-at-point 'line t)))
    (if (and line (string-match "^\\(.*?\\) \\(" line))
        (expand-file-name (match-string 1 line) my-time-machine-dir)
      nil)))

(defun tm-show-diff ()
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
  (interactive)
  (let ((backup (tm--get-current-backup-file))
        (orig-buf tm--target-buf)
        (auto-state tm--auto-save-state)
        (tm-buf (current-buffer)))
    (when (and backup (file-exists-p backup))
      (when (buffer-live-p tm--diff-buf) (kill-buffer tm--diff-buf))
      (ediff-files backup tm--target-file)
      (add-hook 'ediff-quit-hook
                `(lambda ()
                   (when ,auto-state
                     (with-current-buffer ,orig-buf
                       (auto-save-visited-mode 1)
                       (message "Ediff merged. Auto-save resumed.")))
                   (when (buffer-live-p ,tm-buf) (kill-buffer ,tm-buf)))
                nil t))))

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
    (when auto-save-was-on
      (auto-save-visited-mode -1)
      (message "Time Machine active. Auto-save paused."))
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
      (forward-line 3))
    (pop-to-buffer tm-buf)))

;; -------------------------------------------------------------------
;; 8. PACKAGE CONFIGURATION (Modular Bindings)
;; -------------------------------------------------------------------

(add-hook 'makefile-mode-hook (lambda () (setq indent-tabs-mode t)))
(add-hook 'makefile-bsdmake-mode-hook (lambda () (setq indent-tabs-mode t)))

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles orderless partial-completion)))))

(require 'recentf)
(setq recentf-max-saved-items 2000)
(setq recentf-auto-cleanup 'never)
(recentf-mode 1)

(use-package vertico 
  :init (vertico-mode 1) 
  :custom (vertico-cycle t))

(add-to-list 'completion-ignored-extensions ".DS_Store")

(use-package consult
  :bind (("M-s l" . consult-line)
         ("M-s r" . consult-ripgrep)
         ("C-c r" . consult-ripgrep)
         ("C-c f" . consult-fd)
         ("C-x b" . consult-buffer)
         ("M-g g" . consult-goto-line)
         ("M-y"   . consult-yank-pop))
  :config
  (setq consult-ripgrep-args "rg --null --line-buffered --color=never --max-columns=1000 --path-separator /   --smart-case --no-heading --with-filename --line-number --search-zip --sort path"))

(use-package embark 
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim))
  :init (setq prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult :hook (embark-collect-mode . consult-preview-at-point-mode))
(use-package marginalia :init (marginalia-mode 1))

(use-package dirvish
  :init (dirvish-override-dired-mode)
  :config (setq dired-listing-switches "-agho --group-directories-first")
  :bind (:map dirvish-mode-map ("TAB" . dirvish-subtree-toggle)))

(use-package projectile :init (projectile-mode 1))
(use-package vundo 
  :bind ("C-x u" . vundo)
  :config (setq vundo-glyph-alist vundo-unicode-symbols))

(use-package avy
  :bind (("C-:" . avy-goto-char)
         ("C-'" . avy-goto-line)))

(use-package magit
  :bind ("C-x g" . magit-status))

(use-package smartparens :hook (prog-mode . smartparens-mode))
(use-package yasnippet :init (yas-global-mode 1))
(use-package yasnippet-snippets)
(use-package wgrep)
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

;; --- The Markdown Bulletproof Engine ---
(defun pb/region-make-todo-list-and-clean (beg end)
  "Convert headings to checkboxes and clean up double checkboxes."
  (interactive
   (if (use-region-p)
       (list (region-beginning) (region-end))
     (list (line-beginning-position) (line-end-position))))
  (save-excursion
    (save-restriction
      (narrow-to-region beg end)
      (goto-char (point-min))
      (while (re-search-forward "^[ \t]*#+[ \t]+" nil t)
        (replace-match "- [ ] "))
      (goto-char (point-min))
      (while (re-search-forward "- \\[ \\][ \t]*- ?\\[ ?\\][ \t]*" nil t)
        (replace-match "- [ ] ")))))

(defun pb/markdown-complete-task ()
  "Toggle markdown checkbox. If checked, append the current date."
  (interactive)
  (let ((line-text (thing-at-point 'line t)))
    (markdown-toggle-gfm-checkbox)
    (when (string-match-p "- \\[ \\]" line-text)
      (end-of-line)
      (insert (format " @done(%s)" (format-time-string "%Y-%m-%d"))))))

(defun pb/markdown-format-buffer ()
  "Run markdownlint --fix on the current buffer safely."
  (interactive)
  (when (and (eq major-mode 'markdown-mode)
             (executable-find "markdownlint"))
    (pb/format-buffer-safely "markdownlint" '("--fix" "--stdin"))))

(use-package markdown-mode
  :mode ("\\.md\\'" . markdown-mode)
  :bind (:map markdown-mode-map
              ("C-c l"   . pb/region-make-todo-list-and-clean)
              ("C-c C-d" . pb/markdown-complete-task)
              ("M-<right>" . markdown-demote-list-item)
              ("M-<left>"  . markdown-promote-list-item)
              ("M-<up>"    . markdown-move-list-item-up)
              ("M-<down>"  . markdown-move-list-item-down)
              ("TAB"       . markdown-cycle)
              ("<backtab>" . markdown-shifttab))
  :init
  (add-hook 'markdown-mode-hook 
            (lambda ()
              (setq-local corfu-auto nil)
              (flyspell-mode 1)
              (visual-line-mode 1)
              (flycheck-mode -1)
              (add-hook 'before-save-hook #'pb/markdown-format-buffer nil t)))
  :config
  (setq markdown-list-indent-width 4))

;; --- Go Mode ---
(use-package go-mode
  :mode "\\.go\\'"
  :hook (go-mode . lsp-deferred)
  :init
  (add-hook 'go-mode-hook 
            (lambda () 
              (add-hook 'before-save-hook #'pb/go-format-buffer nil t))))

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

;; -------------------------------------------------------------------
;; 9. TYPST SUPPORT (macOS Only + Live Sync Viewer)
;; -------------------------------------------------------------------
(when (eq system-type 'darwin)

  ;; 1. Auto-Compile the Tree-Sitter Grammar
  (require 'treesit nil t)
  (when (and (fboundp 'treesit-language-available-p)
             (not (treesit-language-available-p 'typst)))
    (add-to-list 'treesit-language-source-alist
                 '(typst "https://github.com/uben0/tree-sitter-typst"))
    (treesit-install-language-grammar 'typst))

  ;; 2. Typst Mode (Standard Installation)
  (use-package typst-ts-mode
    :ensure t
    :mode "\\.typ\\'"
    :hook (typst-ts-mode . (lambda ()
                             (lsp-deferred)
                             (setq-local compile-command (format "typst compile %s" buffer-file-name)))))

  ;; 3. The Magic Viewer (WebSockets Live Sync)
  (use-package typst-preview
    :ensure t
    :after typst-ts-mode
    :bind (:map typst-ts-mode-map
                ("C-c C-p" . typst-preview-mode)   ;; Fixed function name
                ("C-c C-s" . typst-preview-send-position))
    :custom
    (typst-preview-executable "tinymist")
    (typst-preview-browser-command "open"))

  ;; 4. Tell lsp-mode how to handle Typst files with Tinymist
  (with-eval-after-load 'lsp-mode
    (add-to-list 'lsp-language-id-configuration '(typst-ts-mode . "typst"))
    (lsp-register-client
     (make-lsp-client :new-connection (lsp-stdio-connection '("tinymist"))
                      :major-modes '(typst-ts-mode)
                      :server-id 'tinymist)))

  ) ;; <--- THIS WAS THE MISSING PARENTHESIS THAT BROKE THE SYNTAX


;; -------------------------------------------------------------------
;; 10. GLOBAL DASHBOARD (Custom Scripts & Overrides Only)
;; -------------------------------------------------------------------

;; Standard Overrides
(global-set-key (kbd "C-s")     #'isearch-forward)
(global-set-key (kbd "C-r")     #'isearch-backward)
(global-set-key (kbd "C-x C-c") 'kill-emacs)

;; Workflow Keys
(global-set-key (kbd "<f5>")    'previous-error)
(global-set-key (kbd "<f6>")    'next-error)
(global-set-key (kbd "<f7>")    'my/delete-note-and-next)
(global-set-key (kbd "<f8>")    'compile)

;; ggo & Obsidian (User Space C-c [letter])
(global-set-key (kbd "C-c c") 'ggo-jump-to-chat)
(global-set-key (kbd "C-c e") 'ggo-ediff-clipboard)
(global-set-key (kbd "C-c o") 'my/open-in-obsidian)
(global-set-key (kbd "C-c t") 'my-time-machine)
(global-set-key (kbd "C-c m") 'pb/reset-mouse)
(global-set-key (kbd "C-c k") 'kill-to-end-of-buffer)
(global-set-key (kbd "C-c a") 'copy-whole-buffer)

;; Custom Clipboard Fix
(global-set-key (kbd "M-w")   'pb/copy-region-and-sync)

(defun my/disable-process-query ()
  (dolist (proc (process-list)) (set-process-query-on-exit-flag proc nil)))
(add-hook 'kill-emacs-hook #'my/disable-process-query)

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(consult-preview-match ((t (:inherit isearch))))
 '(isearch ((t (:background "#aa00aa" :foreground "white" :weight bold))))
 '(lazy-highlight ((t (:background "#0000aa" :foreground "white" :weight bold)))))
(set-face-attribute 'region nil :background "#FFE4B5" :foreground "#000000")

(provide 'init)
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(avy bazel clipetty corfu debian-el diff-hl dirvish dockerfile-mode
         embark-consult flycheck go-mode helm-ls-git helm-rg json-mode
         kind-icon lsp-ui magit marginalia orderless projectile
         rpm-spec-mode rust-mode smartparens swift-mode typst-preview
         vertico vterm vundo wgrep which-key yaml-mode
         yasnippet-snippets))
 '(safe-local-variable-values
   '((typst-preview--master-file
      . "/Users/braam/sw/stg/stg-paper/paper.typ"))))
;;; init.el ends here

;; -------------------------------------------------------------------
;; 10. GLOBAL DASHBOARD (Custom Scripts & Overrides Only)
;; -------------------------------------------------------------------

;; Standard Overrides
(global-set-key (kbd "C-s")     #'isearch-forward)
(global-set-key (kbd "C-r")     #'isearch-backward)
(global-set-key (kbd "C-x C-c") 'kill-emacs)

;; Workflow Keys
(global-set-key (kbd "<f5>")    'previous-error)
(global-set-key (kbd "<f6>")    'next-error)
(global-set-key (kbd "<f7>")    'my/delete-note-and-next)
(global-set-key (kbd "<f8>")    'compile)


;; ggo & Obsidian (User Space C-c [letter])
(global-set-key (kbd "C-c c") 'ggo-jump-to-chat)
(global-set-key (kbd "C-c e") 'ggo-ediff-clipboard)
(global-set-key (kbd "C-c o") 'my/open-in-obsidian)
(global-set-key (kbd "C-c t") 'my-time-machine)
(global-set-key (kbd "C-c m") 'pb/reset-mouse)
(global-set-key (kbd "C-c k") 'kill-to-end-of-buffer)
(global-set-key (kbd "C-c a") 'copy-whole-buffer)

;; Custom Clipboard Fix
(global-set-key (kbd "M-w")   'pb/copy-region-and-sync)

(defun my/disable-process-query ()
  (dolist (proc (process-list)) (set-process-query-on-exit-flag proc nil)))
(add-hook 'kill-emacs-hook #'my/disable-process-query)


(set-face-attribute 'region nil :background "#FFE4B5" :foreground "#000000")

(provide 'init)

;;; init.el ends here
