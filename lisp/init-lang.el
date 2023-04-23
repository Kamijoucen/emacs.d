(use-package eglot
  :hook ((go-mode
          java-mode) . eglot-ensure)
  :bind (("C-c e f" . #'eglot-format)
         ("C-c e a" . #'eglot-code-actions)
         ("C-c e i" . #'eglot-code-action-organize-imports)
         ("C-c e q" . #'eglot-code-action-quickfix))
  :config
  ;; (setq eglot-ignored-server-capabilities '(:documentHighlightProvider))
  (defun eglot-actions-before-save()
    (add-hook 'before-save-hook
              (lambda ()
                (call-interactively #'eglot-format)
                (call-interactively #'eglot-code-action-organize-imports))))
  (add-hook 'eglot--managed-mode-hook #'eglot-actions-before-save))

;; https://github.com/joaotavora/eglot/discussions/888#discussioncomment-2386710
(cl-defmethod eglot-execute-command
  (_server (_cmd (eql java.apply.workspaceEdit)) arguments)
  "Eclipse JDT breaks spec and replies with edits as arguments."
  (mapc #'eglot--apply-workspace-edit arguments))

(cl-defgeneric +eglot/ext-uri-to-path (uri)
  "Support extension uri."
  nil)

;; https://github.com/eclipse/eclipse.jdt.ls/blob/b4e5cb4b693d5d503d90be89b0b9a8abe9db41a5/org.eclipse.jdt.ls.core/src/org/eclipse/jdt/ls/core/internal/JDTUtils.java#L809
(cl-defmethod +eglot/ext-uri-to-path (uri &context (major-mode java-mode))
  "Support Eclipse jdtls `jdt://' uri scheme."
  (when-let* ((jdt-scheme-p (string-prefix-p "jdt://" uri))
              (filename (save-match-data
                          (when (string-match "jdt://contents/\\(.*?\\)/\\(.*\\)\.class\\?" uri)
                            (format "%s.java"
                                    (replace-regexp-in-string "/" "." (match-string 2 uri) t t))))))
    (+eglot/create-source-file :java/classFileContents uri filename)))

;; https://github.com/emacs-lsp/lsp-mode/blob/d3bc47bde5ffc1bace40122a6ec0c6d8b9e84500/clients/lsp-clojure.el#L272
;; https://github.com/clojure-lsp/clojure-lsp/blob/master/lib/test/clojure_lsp/shared_test.clj
(cl-defmethod +eglot/ext-uri-to-path (uri &context (major-mode clojure-mode))
  "Support Clojure-lsp `zifile://', `jar:file://' uri scheme."
  (when-let* ((clj-scheme-p (or (string-prefix-p "jar:file://" uri)
                                (string-prefix-p "zipfile://" uri)))
              (filename (when (string-match "^\\(jar:file\\|zipfile\\)://.+\\(!/\\|::\\)\\(.+\\)" uri)
                          (let* ((ns-path (match-string 3 uri))
                                 (filename (replace-regexp-in-string "/" "." ns-path)))
                            filename))))
    (+eglot/create-source-file :clojure/dependencyContents uri filename)))

(defun +eglot/create-source-file (method uri filename)
  "Create source file and metadata in project root .eglot directory."
  (let* ((cache-dir (file-name-concat (project-root (eglot--current-project)) ".eglot"))
         (source-file (expand-file-name (file-name-concat cache-dir filename))))
    (unless (file-readable-p source-file)
      (let ((content (jsonrpc-request (eglot--current-server-or-lose) method (list :uri uri)))
            (metadata-file (+eglot/path-to-metadata-file source-file)))
        (unless (file-directory-p cache-dir) (make-directory cache-dir t))
        (with-temp-file source-file (insert content))
        (with-temp-file metadata-file (insert uri))))
    source-file))

(defun +eglot/path-to-metadata-file (path)
  (format "%s.%s.metadata" (file-name-directory path) (file-name-base path)))

(defun +eglot/path-to-ext-uri (path)
  "Retrieve extension uri from metadata."
  (let ((metadata-file (+eglot/path-to-metadata-file path)))
    (when (file-exists-p metadata-file)
      (with-temp-buffer
        (insert-file-contents metadata-file)
        (buffer-string)))))

(define-advice eglot--uri-to-path (:around (orig-fn uri) advice)
  "Support non standard LSP uri scheme."
  (when (keywordp uri) (setq uri (substring (symbol-name uri) 1)))
  (or (+eglot/ext-uri-to-path uri)
      (funcall orig-fn uri)))

(define-advice eglot--path-to-uri (:around (orig-fn path) advice)
  "Support non standard LSP uri scheme."
  (or (+eglot/path-to-ext-uri path)
      (funcall orig-fn path)))

(provide 'init-lang)
