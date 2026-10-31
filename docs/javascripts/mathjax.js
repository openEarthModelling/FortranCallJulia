// MathJax 3 config for pymdownx.arithmatex (generic mode), per the
// Material for MkDocs math recipe. Loaded before the MathJax bundle
// (see extra_javascript order in mkdocs.yml).
window.MathJax = {
  tex: {
    inlineMath: [["\\(", "\\)"]],
    displayMath: [["\\[", "\\]"]],
    processEscapes: true,
    processEnvironments: true
  },
  options: {
    ignoreHtmlClass: ".*|",
    processHtmlClass: "arithmatex"
  }
};

document$.subscribe(() => {
  MathJax.typesetPromise()
});
