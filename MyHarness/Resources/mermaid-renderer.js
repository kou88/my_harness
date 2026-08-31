"use strict";

let configuredTheme = null;
let newestRequest = 0;

async function renderDiagram(source, requestID, theme) {
  newestRequest = requestID;
  const diagram = document.getElementById("diagram");
  diagram.replaceChildren();
  if (configuredTheme === null) {
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      theme,
      maxTextSize: 50000,
      flowchart: { htmlLabels: false, useMaxWidth: false }
    });
    configuredTheme = theme;
  }
  try {
    const result = await mermaid.render(`diagram-${requestID}`, source);
    if (requestID !== newestRequest) return false;
    diagram.innerHTML = result.svg;
    const svg = diagram.querySelector("svg");
    if (svg) {
      svg.style.width = "auto";
      svg.style.height = "auto";
      svg.style.maxWidth = "none";
    }
    await new Promise(requestAnimationFrame);
    window.webkit.messageHandlers.mermaid.postMessage({
      status: "rendered", requestID, height: Math.ceil(document.documentElement.scrollHeight)
    });
    return true;
  } catch (error) {
    if (requestID !== newestRequest) return false;
    diagram.replaceChildren();
    window.webkit.messageHandlers.mermaid.postMessage({ status: "error", requestID });
    return false;
  }
}
