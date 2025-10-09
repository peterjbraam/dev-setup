;;; init.el --- portable, devcontainer Emacs config  -*- lexical-binding: t; -*-

;; -------------------------------------------------------------------
;; Package bootstrap
;; -------------------------------------------------------------------

(global-set-key (kbd "C-x C-c") 'kill-emacs)

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
;; UI: fast & readable
;; -------------------------------------------------------------------
(menu-bar-mode -1)
(when (display-graphic-p)
  (tool-bar-mode -1)
  (scroll-bar-mode -1))
(setq inhibit-startup-message t)
(global-display-line-numbers-mode 1)
(column-number-mode 1)
(setq-default indent-tabs-mode nil tab-width 4)

;; ================================================
;; Region handi tools
;; ================================================


(defun kill-to-end-of-buffer ()
  "Kill from point to the end of the buffer."
  (interactive)
  (kill-region (point) (point-max)))

(global-set-key (kbd "C-c k") 'kill-to-end-of-buffer)

(defun copy-whole-buffer ()
  "Copy the entire buffer to the kill ring."
  (interactive)
  (kill-new (buffer-substring-no-properties (point-min) (point-max)))
  (message "Entire buffer copied"))

(global-set-key (kbd "C-c a") 'copy-whole-buffer)

;; ===================================
;; THEME
;; ===================================

(when (not (display-graphic-p))
  ;; only set this theme for terminal emacs
  (load-theme 'wombat t))

;; ===================================
;; auto saving
;; ===================================

(setq auto-save-visited-interval 2)
(auto-save-visited-mode 1)
(setq make-backup-files nil create-lockfiles nil)

(defvar my-smart-backup-dir (expand-file-name "~/.emacs.d/timebackups/")
  "Directory to store smart timestamped backups.")

(defun my--backup-bucket ()
  "Return the appropriate backup time bucket symbol for current time."
  (let ((sec (string-to-number (format-time-string "%S")))
        (min (string-to-number (format-time-string "%M"))))
    (cond
     ((zerop (% min 2)) '2min)
     ((zerop (% min 5)) '5min)
     ((zerop (% min 60)) '1h)
     ((zerop (% min 1440)) '1d) ;; once every day
     (t nil))))

(defun my--bucket-time-prefix (bucket)
  "Return a prefix regex to match backups in the same time bucket."
  (let ((file (file-name-nondirectory (or buffer-file-name ""))))
    (concat (regexp-quote (expand-file-name file my-smart-backup-dir))
            "\\."
            (pcase bucket
              ('2min "\\([0-9]\\{8\\}-[0-9]\\{4\\}\\)[0-9][0-9]")
              ('5min "\\([0-9]\\{8\\}-[0-9]\\{4\\}\\)[0-9][0-9]")
              ('1h   "\\([0-9]\\{8\\}-[0-9]\\{2\\}\\)[0-9][0-9]")
              ('1d   "\\([0-9]\\{8\\}\\)[0-9][0-9]"))
            "$")))

(defun my--cleanup-old-backups (bucket)
  "Remove old backups in the same time bucket except the most recent."
  (let* ((file (file-name-nondirectory buffer-file-name))
         (prefix-re (my--bucket-time-prefix bucket))
         (backups (directory-files my-smart-backup-dir t prefix-re)))
    (when (> (length backups) 1)
      (dolist (f (butlast (sort backups #'string>)))
        (delete-file f)))))

(defun my-smart-backup ()
  "Perform a timestamped backup for the current buffer into the appropriate time bucket."
  (when (and buffer-file-name (file-writable-p buffer-file-name))
    (let ((bucket (my--backup-bucket)))
      (when bucket
        (let* ((file (file-name-nondirectory buffer-file-name))
               (stamp (format-time-string "%Y%m%d-%H%M%S"))
               (target (expand-file-name (format "%s.%s" file stamp) my-smart-backup-dir)))
          (make-directory my-smart-backup-dir t)
          (copy-file buffer-file-name target t)
          (my--cleanup-old-backups bucket)
          (message "Smart backup saved: %s [%s]" target bucket))))))

;; Run every minute — lightweight
(run-with-timer 10 60 (lambda () (save-excursion
                                   (dolist (buf (buffer-list))
                                     (with-current-buffer buf
                                       (when (buffer-file-name)
                                         (my-smart-backup)))))))

;; -------------------------------------------------------------------
;; Terminal and mouse
;; -------------------------------------------------------------------

(setenv "TERM" "xterm-256color")

;; Enable mouse interaction in all environments
(xterm-mouse-mode 1) ; necessary for terminals
(mouse-wheel-mode 1)

;; Smooth scrolling
(setq mouse-wheel-scroll-amount '(1 ((shift) . 5)))
(setq mouse-wheel-progressive-speed nil)
(setq mouse-wheel-follow-mouse t)

;; Scroll with mouse buttons in terminal
(when (not (display-graphic-p))
  (global-set-key [mouse-4] (lambda () (interactive) (scroll-down 1)))
  (global-set-key [mouse-5] (lambda () (interactive) (scroll-up 1))))

;; Allow mouse click to set point (cursor)
(global-set-key [mouse-1] 'mouse-set-point)
(global-set-key [down-mouse-1] 'mouse-drag-region)

;; -------------------------------------------------------------------
;; Cross platform copy paste
;; -------------------------------------------------------------------
;; Keep Emacs kill-ring separate from system clipboard
(setq select-enable-clipboard nil)
(setq select-enable-primary nil)
(setq save-interprogram-paste-before-kill t)
(setq interprogram-cut-function nil)
(setq interprogram-paste-function nil)


(defun pb/osc52-copy (text &optional _push)
  "Send TEXT to system clipboard via OSC 52 escape sequence."
  (when (and text (stringp text))
    (send-string-to-terminal
     (concat "\e]52;c;" (base64-encode-string text t) "\a"))))

(setq interprogram-cut-function #'pb/osc52-copy)

;; -------------------------------------------------------------------
;; Delayed clipboard sync after region selection (mouse or keyboard)
;; -------------------------------------------------------------------

(defvar pb/osc52-idle-timer nil
  "Timer to delay clipboard sync after region selection.")

(defun pb/osc52-copy (text &optional _push)
  "Send TEXT to system clipboard via OSC 52 escape sequence."
  (when (and text (stringp text))
    (send-string-to-terminal
     (concat "\e]52;c;" (base64-encode-string text t) "\a"))))

(setq interprogram-cut-function #'pb/osc52-copy)

(defun pb/osc52-sync-if-region ()
  "Copy region to kill ring and OSC 52 clipboard, if region is active and non-empty."
  (when (use-region-p)
    (let ((text (buffer-substring-no-properties (region-beginning) (region-end))))
      (when (> (length text) 2)
        (kill-new text)
        (pb/osc52-copy text)
        (message "✅ Region copied to kill ring and system clipboard")))))

(defun pb/osc52-delay-sync ()
  "Schedule delayed region sync after idle timeout."
  (when pb/osc52-idle-timer
    (cancel-timer pb/osc52-idle-timer))
  (setq pb/osc52-idle-timer
        (run-with-idle-timer 1.0 nil #'pb/osc52-sync-if-region)))

(advice-add 'mouse-drag-region :after (lambda (&rest _) (pb/osc52-delay-sync)))
(add-hook 'activate-mark-hook #'pb/osc52-delay-sync)
(add-hook 'post-command-hook #'pb/osc52-delay-sync)

    (setq interprogram-paste-function
      (lambda ()
        (with-temp-buffer
          (call-process "pbpaste" nil t)
          (let ((text (buffer-string)))
            (unless (string= text (car kill-ring))
              text)))))

(defun pb/reset-mouse ()
  "Toggle xterm-mouse-mode to reinitialize mouse handling."
  (interactive)
  (xterm-mouse-mode -1)
  (xterm-mouse-mode 1)
  (message "Mouse reset"))
(global-set-key (kbd "C-c m") 'pb/reset-mouse)

(global-set-key (kbd "<triple-mouse-1>") 'move-beginning-of-line)


;; Containers
(require 'tramp-container)



;; -------------------------------------------------------------------
;; Completion & Navigation: Vertico + Orderless + Marginalia + Consult
;; -------------------------------------------------------------------
(use-package orderless
  :custom
  (completion-styles '(orderless))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles partial-completion)))))

(use-package vertico :init (vertico-mode 1) :custom (vertico-cycle t))
(use-package marginalia :init (marginalia-mode 1))

(use-package consult) ;; yank history (fuzzy)

(use-package embark
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim))
  :init (setq prefix-help-command #'embark-prefix-help-command))
(use-package embark-consult :hook (embark-collect-mode . consult-preview-at-point-mode))

;; In-buffer completion popup
(use-package corfu :init (global-corfu-mode 1) :custom (corfu-auto t))
(use-package kind-icon
  :after corfu
  :custom (kind-icon-default-face 'corfu-default)
  :config (add-to-list 'corfu-margin-formatters #'kind-icon-margin-formatter))

;; Projects & workspaces (git/submodules friendly)
(use-package projectile
  :init (projectile-mode 1)
  :custom ((projectile-enable-caching t)
           (projectile-git-submodule-command "git submodule --quiet foreach 'echo $sm_path'"))
  :bind-keymap ("C-c p" . projectile-command-map))

;; Easy last-buffer switch
(global-set-key (kbd "C-<tab>") #'mode-line-other-buffer)

;; -------------------------------------------------------------------
;; Git & patches
;; -------------------------------------------------------------------
(use-package magit :commands (magit-status magit-dispatch))
(with-eval-after-load 'magit
  (global-set-key (kbd "C-x g") 'magit-status)) ;; quick entry
(use-package diff-hl
  :hook ((prog-mode . diff-hl-mode)
         (magit-post-refresh . diff-hl-magit-post-refresh)))

;; -------------------------------------------------------------------
;; Markdown (+ yank fenced code helper) + Outline folding
;; -------------------------------------------------------------------
(use-package markdown-mode
  :mode (("\\.md\\'" . markdown-mode)
         ("README\\.md\\'" . gfm-mode))
  :custom (markdown-command "pandoc")
  :init
  (defun pb/markdown-outline-setup ()
    (setq-local outline-regexp "^\\(#{1,6}\\)\\s-+\\(.+\\)$")
    (outline-minor-mode 1))
  :hook (markdown-mode . pb/markdown-outline-setup))

(with-eval-after-load 'markdown-mode
  (define-key markdown-mode-map (kbd "<tab>")    #'markdown-cycle)
  (define-key markdown-mode-map (kbd "S-<tab>")  #'markdown-shifttab))

(defun pb/yank-markdown-code-block ()
  "If point is inside a fenced code block, yank its contents to kill-ring."
  (interactive)
  (save-excursion
    (when (re-search-backward "^```" nil t)
      (let ((beg (match-end 0)))
        (when (re-search-forward "^```" nil t)
          (let ((end (match-beginning 0)))
            (kill-new (buffer-substring-no-properties beg end))
            (message "Code block yanked.")))))))
(global-set-key (kbd "C-c y") #'pb/yank-markdown-code-block)

;; -------------------------------------------------------------------
;; Build & compilation
;; -------------------------------------------------------------------

(setq compilation-scroll-output t)
(global-set-key (kbd "C-c m") (lambda () (interactive) (compile "make -k")))
;; M-x compile to change; M-x recompile to repeat; M-g n / M-g p to jump errors

;; -------------------------------------------------------------------
;; Terminals
;; -------------------------------------------------------------------
(use-package vterm :when (not (eq system-type 'windows-nt)))

;; -------------------------------------------------------------------
;; LSP & languages
;; -------------------------------------------------------------------
(use-package lsp-mode
  :commands (lsp lsp-deferred)
  :hook ((go-mode         . lsp-deferred)
         (sh-mode         . lsp-deferred)
         (json-mode       . lsp-deferred)
         (yaml-mode       . lsp-deferred)
;;         (dockerfile-mode . lsp-deferred)
         (markdown-mode   . lsp-deferred))
  :custom
  (lsp-prefer-flymake nil)
  (lsp-completion-provider :none)) ;; let corfu handle UI

(use-package lsp-ui :commands lsp-ui-mode)

;; Go / Shell / JSON / YAML / Docker / Packer / Bazel
(use-package go-mode :mode "\\.go\\'")
(use-package json-mode   :mode "\\.json\\'")
(use-package yaml-mode   :mode "\\.ya?ml\\'")
(use-package dockerfile-mode
  :ensure t)
(add-to-list 'auto-mode-alist '("\\.docker\\'" . dockerfile-mode))
(use-package bazel
  :mode (("\\.bzl\\'" . bazel-mode)
         ("WORKSPACE\\'" . bazel-workspace-mode)
         ("BUILD\\(\\.bazel\\)?\\'" . bazel-build-mode)))

;; Makefiles (built-in)
(add-to-list 'auto-mode-alist '("Makefile\\'" . makefile-gmake-mode))

;; -------------------------------------------------------------------
;; Manifests: Brewfile / RPM spec / Debian control + Flycheck validators
;; -------------------------------------------------------------------
;; Brewfile as Ruby DSL
(add-to-list 'auto-mode-alist '("Brewfile\\'" . ruby-mode))

(use-package rpm-spec-mode :mode "\\.spec\\'")
(use-package debian-el
  :mode (("debian/control\\'"   . debian-control-mode)
         ("debian/changelog\\'" . debian-changelog-mode)
         ("debian/rules\\'"     . makefile-gmake-mode)))

(use-package flycheck :init (global-flycheck-mode 1))

;; Brewfile validator
(flycheck-define-checker brew-bundle
  "Validate Brewfile with `brew bundle check`."
  :command ("brew" "bundle" "check" "--file" source)
  :error-patterns
  ((warning line-start (message "Warning:" (one-or-more not-newline)) line-end)
   (error line-start "Error: " (message (one-or-more not-newline)) line-end))
  :modes (ruby-mode)
  :predicate (lambda () (and buffer-file-name (string-match-p "Brewfile\\'" buffer-file-name))))
(add-to-list 'flycheck-checkers 'brew-bundle)

;; rpmlint for .spec
(flycheck-define-checker rpmlint
  "Lint RPM spec files with rpmlint."
  :command ("rpmlint" "-i" source)
  :error-patterns
  ((error   line-start (file-name) ":" line ": E: " (message) line-end)
   (warning line-start (file-name) ":" line ": W: " (message) line-end)
   (info    line-start (file-name) ":" line ": I: " (message) line-end))
  :modes (rpm-spec-mode)
  :predicate (lambda () (executable-find "rpmlint")))
(add-to-list 'flycheck-checkers 'rpmlint)

;; lintian for Debian control/changelog (run in source tree)
(flycheck-define-checker lintian
  "Run lintian in the file's directory (expects a Debian source tree)."
  :command ("bash" "-lc" "lintian --no-cfg --info --display-info --pedantic . 2>&1 || true")
  :error-patterns
  ((error   line-start (any "E" "X") ": " (message) line-end)
   (warning line-start "W: " (message) line-end)
   (info    line-start "I: " (message) line-end))
  :modes (debian-control-mode debian-changelog-mode)
  :working-directory (lambda (_) default-directory)
  :predicate (lambda () (executable-find "lintian")))
(add-to-list 'flycheck-checkers 'lintian)

;; Optional: apt/rpm package list files as conf-mode
(add-to-list 'auto-mode-alist '("apt-packages\\.txt\\'" . conf-mode))
(add-to-list 'auto-mode-alist '("rpm-packages\\.txt\\'" . conf-mode))
(flycheck-define-checker apt-package-list
  "Verify each non-comment token exists in APT metadata."
  :command ("bash" "-lc"
            "awk 'BEGIN{rc=0} /^[#[:space:]]*$/ {next} {cmd=\"apt-cache show \"$1\" >/dev/null 2>&1\"; rc=system(cmd); if (rc!=0){print NR\":\"$1}}' ${INPUT}" source)
  :error-patterns ((error line-start line ":" (message) line-end))
  :modes (conf-mode)
  :predicate (lambda () (and (executable-find "apt-cache")
                             (string-match-p "apt-packages\\.txt\\'" (buffer-name)))))
(add-to-list 'flycheck-checkers 'apt-package-list)

(use-package flycheck
  :ensure t
  :init (global-flycheck-mode))

(flycheck-define-checker yaml-yamllint
  "A YAML syntax and style checker using yamllint."
  :command ("yamllint" "-f" "parsable" source)
  :error-patterns
  ((warning line-start (file-name) ":" line ":" column ": "
            (id (one-or-more not-newline) ":") (message) line-end))
  :modes (yaml-mode))

(add-to-list 'flycheck-checkers 'yaml-yamllint)


;; -------------------------------------------------------------------
;; Quit check for perhaps important processes
;; -------------------------------------------------------------------
(defun my/disable-process-query ()
  "Disable query-on-exit for harmless background processes."
  (dolist (proc (process-list))
    (when (member (process-name proc) '("pbcopy" "bash" "sh"))
      (set-process-query-on-exit-flag proc nil))))

(add-hook 'kill-emacs-hook #'my/disable-process-query)

;; -------------------------------------------------------------------
;; QoL
;; -------------------------------------------------------------------
(use-package which-key :init (which-key-mode 1))

(provide 'init)
(use-package yaml-mode
  :ensure t
  :mode ("\\.ya?ml\\'" . yaml-mode))
;; (use-package dockerfile-mode :mode "Dockerfile\\'")

(use-package bazel
  :mode (("\\.bzl\\'" . bazel-mode)
         ("WORKSPACE\\'" . bazel-workspace-mode)
         ("BUILD\\(\\.bazel\\)?\\'" . bazel-build-mode)))

;; Makefiles (built-in)
(add-to-list 'auto-mode-alist '("Makefile\\'" . makefile-gmake-mode))

;; -------------------------------------------------------------------
;; Manifests: Brewfile / RPM spec / Debian control + Flycheck validators
;; -------------------------------------------------------------------
;; Brewfile as Ruby DSL
(add-to-list 'auto-mode-alist '("Brewfile\\'" . ruby-mode))

(use-package rpm-spec-mode :mode "\\.spec\\'")
(use-package debian-el
  :mode (("debian/control\\'"   . debian-control-mode)
         ("debian/changelog\\'" . debian-changelog-mode)
         ("debian/rules\\'"     . makefile-gmake-mode)))

(use-package flycheck :init (global-flycheck-mode 1))

;; Brewfile validator
(flycheck-define-checker brew-bundle
  "Validate Brewfile with `brew bundle check`."
  :command ("brew" "bundle" "check" "--file" source)
  :error-patterns
  ((warning line-start (message "Warning:" (one-or-more not-newline)) line-end)
   (error line-start "Error: " (message (one-or-more not-newline)) line-end))
  :modes (ruby-mode)
  :predicate (lambda () (and buffer-file-name (string-match-p "Brewfile\\'" buffer-file-name))))
(add-to-list 'flycheck-checkers 'brew-bundle)

;; rpmlint for .spec
(flycheck-define-checker rpmlint
  "Lint RPM spec files with rpmlint."
  :command ("rpmlint" "-i" source)
  :error-patterns
  ((error   line-start (file-name) ":" line ": E: " (message) line-end)
   (warning line-start (file-name) ":" line ": W: " (message) line-end)
   (info    line-start (file-name) ":" line ": I: " (message) line-end))
  :modes (rpm-spec-mode)
  :predicate (lambda () (executable-find "rpmlint")))
(add-to-list 'flycheck-checkers 'rpmlint)

;; lintian for Debian control/changelog (run in source tree)
(flycheck-define-checker lintian
  "Run lintian in the file's directory (expects a Debian source tree)."
  :command ("bash" "-lc" "lintian --no-cfg --info --display-info --pedantic . 2>&1 || true")
  :error-patterns
  ((error   line-start (any "E" "X") ": " (message) line-end)
   (warning line-start "W: " (message) line-end)
   (info    line-start "I: " (message) line-end))
  :modes (debian-control-mode debian-changelog-mode)
  :working-directory (lambda (_) default-directory)
  :predicate (lambda () (executable-find "lintian")))
(add-to-list 'flycheck-checkers 'lintian)

;; Optional: apt/rpm package list files as conf-mode
(add-to-list 'auto-mode-alist '("apt-packages\\.txt\\'" . conf-mode))
(add-to-list 'auto-mode-alist '("rpm-packages\\.txt\\'" . conf-mode))
(flycheck-define-checker apt-package-list
  "Verify each non-comment token exists in APT metadata."
  :command ("bash" "-lc"
            "awk 'BEGIN{rc=0} /^[#[:space:]]*$/ {next} {cmd=\"apt-cache show \"$1\" >/dev/null 2>&1\"; rc=system(cmd); if (rc!=0){print NR\":\"$1}}' ${INPUT}" source)
  :error-patterns ((error line-start line ":" (message) line-end))
  :modes (conf-mode)
  :predicate (lambda () (and (executable-find "apt-cache")
                             (string-match-p "apt-packages\\.txt\\'" (buffer-name)))))
(add-to-list 'flycheck-checkers 'apt-package-list)


;; -------------------------------------------------------------------
;; QoL
;; -------------------------------------------------------------------
(use-package which-key :init (which-key-mode 1))
(use-package yaml-mode
  :ensure t
    :mode ("\\.ya?ml\\'" . yaml-mode))

;; Restore keybinding taken by packages
(global-set-key (kbd "C-s") #'isearch-forward)
(global-set-key (kbd "C-r") #'isearch-backward)

(provide 'init)
;;; init.el ends here

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(bazel copilot corfu debian-el diff-hl dockerfile-mode embark-consult
           flycheck go-mode gptel json-mode kind-icon lsp-ui magit
           marginalia orderless projectile rpm-spec-mode vertico vterm
           websocket yaml yaml-mode)))

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
