;;; init.el --- portable, devcontainer-friendly Emacs config  -*- lexical-binding: t; -*-

;; -------------------------------------------------------------------
;; Package bootstrap
;; -------------------------------------------------------------------
(require 'package)
(setq package-archives
      '(("gnu"   . "https://elpa.gnu.org/packages/")
        ("melpa" . "https://melpa.org/packages/")))
(setq package-enable-at-startup nil)
(package-initialize)
(unless (package-installed-p 'use-package)
  (package-refresh-contents) (package-install 'use-package))
(eval-when-compile (require 'use-package))
(setq use-package-always-ensure t)

;; -------------------------------------------------------------------
;; UI: fast & readable
;; -------------------------------------------------------------------
(menu-bar-mode -1) (tool-bar-mode -1) (scroll-bar-mode -1)
(setq inhibit-startup-message t)
(global-display-line-numbers-mode 1)
(column-number-mode 1)
(setq-default indent-tabs-mode nil tab-width 2)

;; Font (JetBrains Mono Nerd Font) if present
(when (find-font (font-spec :name "JetBrainsMono Nerd Font"))
  (set-face-attribute 'default nil :font "JetBrainsMono Nerd Font-12"))

;; Colorize compilation buffers
(use-package ansi-color :ensure nil
  :hook (compilation-filter . (lambda () (ansi-color-apply-on-region (point-min) (point-max)))))

;; Save behavior
(setq auto-save-visited-interval 2)
(auto-save-visited-mode 1)
(setq make-backup-files nil create-lockfiles nil)

;; Terminal & mouse
(xterm-mouse-mode 1)
(setq system-uses-terminfo t) ;; keep tmux happy

;; -------------------------------------------------------------------
;; System clipboard integration (mac GUI/TTY, iPad SSH via OSC52)
;; -------------------------------------------------------------------
(setq select-enable-clipboard t
      select-enable-primary t)

;; macOS pbcopy/pbpaste bridge for terminal Emacs
(unless (display-graphic-p)
  (when (executable-find "pbcopy")
    (setq interprogram-cut-function
          (lambda (text &optional _push)
            (let ((p (start-process "pbcopy" nil "pbcopy")))
              (process-send-string p text)
              (process-send-eof p)))))
  (when (executable-find "pbpaste")
    (setq interprogram-paste-function
          (lambda ()
            (with-temp-buffer
              (call-process "pbpaste" nil t nil)
              (buffer-string))))))

;; OSC52 clipboard for any TTY (incl. iPad Blink/Termius)
(use-package osc52
  :config
  (setq osc52-max-length 100000)
  (unless (display-graphic-p)
    (setq interprogram-cut-function
          (lambda (text &optional _push)
            (when (stringp text) (osc52-set-clipboard text)))
          interprogram-paste-function nil)))

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

(use-package consult
  :bind (("C-s"     . consult-line)           ;; in-buffer search
         ("C-S-s"   . consult-ripgrep)        ;; project/global search
         ("C-x b"   . consult-buffer)         ;; switch buffers/recent
         ("M-g i"   . consult-imenu)
         ("M-y"     . consult-yank-pop)))     ;; yank history (fuzzy)

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
         (dockerfile-mode . lsp-deferred)
         (markdown-mode   . lsp-deferred))
  :custom
  (lsp-prefer-flymake nil)
  (lsp-completion-provider :none)) ;; let corfu handle UI

(use-package lsp-ui :commands lsp-ui-mode)

;; Go / Shell / JSON / YAML / Docker / Packer / Bazel
(use-package go-mode :mode "\\.go\\'")
(use-package json-mode   :mode "\\.json\\'")
(use-package yaml-mode   :mode "\\.ya?ml\\'")
(use-package dockerfile-mode :mode "Dockerfile\\'")
(use-package packer :commands packer-mode
  :mode (("\\.pkr\\(\\.hcl\\)?\\'" . packer-mode)
         ("\\.pkr\\.json\\'"       . packer-mode)))
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
;; Devcontainers & remote editing
;; -------------------------------------------------------------------
(use-package docker-tramp)  ;; open with /docker:container:/path
(setq tramp-default-method "ssh")

;; -------------------------------------------------------------------
;; AI: Copilot ghost text
;; -------------------------------------------------------------------
(use-package copilot
  :hook (prog-mode . copilot-mode)
  :bind (:map prog-mode-map
         ("C-<return>"   . copilot-accept-completion)
         ("C-M-<return>" . copilot-accept-completion-by-word)))
(add-hook 'minibuffer-setup-hook
          (lambda () (when (bound-and-true-p copilot-mode) (copilot-mode -1))))

;; -------------------------------------------------------------------
;; AI: gptel (Gemini) + autosave transcripts + context helpers
;; -------------------------------------------------------------------
(setq-default gptel-system-prompt "Next issue, remember the work agreement:")
(setq-default pb/gptel-context-files nil) ;; per-project via .dir-locals.el

(use-package gptel
  :config
  (gptel-make-openai "Gemini"
    :host "generativelanguage.googleapis.com"
    :endpoint "/v1beta/models/%s:generateContent"
    :key (getenv "GEMINI_API_KEY")
    :models '("gemini-1.5-pro" "gemini-1.5-flash"))
  (setq gptel-backend (gptel-get-backend "Gemini")
        gptel-model   "gemini-1.5-pro"))

;; Autosave transcripts
(defgroup pb-gptel nil "Autosave transcripts for gptel." :group 'external)
(defcustom pb/gptel-log-dir (expand-file-name "~/gptel-logs")
  "Directory where gptel chat transcripts are stored." :type 'directory)

(defun pb/gptel--make-log-path (&optional title)
  (let* ((ts (format-time-string "%Y-%m-%d--%H%M%S"))
         (name (or (and title (replace-regexp-in-string "[^A-Za-z0-9._-]+" "_" title))
                   "chat"))
         (file (format "%s--%s.md" ts name)))
    (expand-file-name file pb/gptel-log-dir)))

(defun pb/gptel-autosave-setup (&optional title)
  "Attach a file to the current gptel buffer and enable autosave."
  (interactive "sOptional title for transcript: ")
  (unless (file-directory-p pb/gptel-log-dir)
    (make-directory pb/gptel-log-dir t))
  (unless buffer-file-name
    (let ((path (pb/gptel--make-log-path title)))
      (when (= (buffer-size) 0)
        (insert (format "# gptel chat (%s)\n\n" (format-time-string "%F %T"))))
      (set-visited-file-name path t t)))
  (setq-local auto-save-visited-interval 5)
  (auto-save-visited-mode 1)
  (save-buffer))

(defun pb/gptel-rename-transcript (new-title)
  "Rename current gptel transcript file based on NEW-TITLE."
  (interactive "sNew title: ")
  (let ((new (pb/gptel--make-log-path new-title)))
    (set-visited-file-name new t t)
    (save-buffer)
    (message "Transcript now: %s" new)))

;; Context helpers
(defvar-local pb/gptel-context-files nil
  "List of files whose contents are injected as chat context in this buffer.")
(defvar-local pb/gptel-context-enabled t
  "Whether to inject pb/gptel-context-files when (re)starting a chat.")

(defun pb/gptel--read-file (f)
  (when (and f (file-readable-p f))
    (with-temp-buffer (insert-file-contents f) (buffer-string))))

(defun pb/gptel-inject-context (&optional quiet)
  "Insert contents of `pb/gptel-context-files` into this gptel chat."
  (interactive)
  (when (and (boundp 'gptel-mode) gptel-mode pb/gptel-context-enabled pb/gptel-context-files)
    (let* ((files (seq-filter #'file-readable-p pb/gptel-context-files))
           (chunks (mapcar (lambda (f)
                             (format "\n[CONTEXT from %s]\n%s\n[END CONTEXT]\n"
                                     (file-name-nondirectory f)
                                     (or (pb/gptel--read-file f) "")))
                           files)))
      (when chunks
        (if (fboundp 'gptel-add-context)
            (dolist (c chunks) (gptel-add-context c))
          (save-excursion (goto-char (point-min)) (insert (apply #'concat chunks) "\n")))
        (unless quiet (message "Injected %d context file(s)." (length chunks)))))))

(defun pb/gptel-toggle-context () (interactive)
  (setq pb/gptel-context-enabled (not pb/gptel-context-enabled))
  (message "Context %s" (if pb/gptel-context-enabled "ENABLED" "DISABLED")))

(defun pb/gptel-reload-context () (interactive) (pb/gptel-inject-context))
(defun pb/gptel-new-chat-with-context () (interactive)
  (when (fboundp 'gptel-new-session) (gptel-new-session))
  (pb/gptel-inject-context))

(with-eval-after-load 'gptel
  (add-hook 'gptel-mode-hook
            (lambda ()
              (pb/gptel-autosave-setup)
              (when (boundp 'gptel-post-response-hook)
                (add-hook 'gptel-post-response-hook #'save-buffer nil t))
              (pb/gptel-inject-context t)))
  (define-key gptel-mode-map (kbd "C-c C-s") #'save-buffer)
  (define-key gptel-mode-map (kbd "C-c C-r") #'pb/gptel-rename-transcript)
  (define-key gptel-mode-map (kbd "C-c C-a") #'pb/gptel-reload-context)
  (define-key gptel-mode-map (kbd "C-c C-t") #'pb/gptel-toggle-context)
  (define-key gptel-mode-map (kbd "C-c C-n") #'pb/gptel-new-chat-with-context))

;; -------------------------------------------------------------------
;; GhostText / Atomic Chrome
;; -------------------------------------------------------------------
(use-package atomic-chrome
  :init (atomic-chrome-start-server)
  :custom (atomic-chrome-buffer-open-style 'frame)) ;; new frame for focus

;; -------------------------------------------------------------------
;; QoL
;; -------------------------------------------------------------------
(use-package which-key :init (which-key-mode 1))
(use-package yaml-pro :after yaml-mode)

(provide 'init)
;;; init.el ends here
