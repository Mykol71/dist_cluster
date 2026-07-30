(() => {
  const article = document.querySelector("#markdown-content");
  const source = document.body.dataset.markdownSource;

  if (!article || !source || typeof marked === "undefined") {
    return;
  }

  fetch(source)
    .then((response) => {
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      return response.text();
    })
    .then((markdown) => {
      article.innerHTML = marked.parse(markdown, { gfm: true });
    })
    .catch((error) => {
      article.innerHTML =
        `<p class="error">Unable to load this document: ${error.message}</p>` +
        `<p><a href="${source}">Open the Markdown source</a></p>`;
    });
})();
