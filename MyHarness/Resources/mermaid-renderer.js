"use strict";

let configuredTheme = null;
let newestRequest = 0;

function dimensions(svg) {
  const viewBox = svg.viewBox && svg.viewBox.baseVal;
  if (viewBox && viewBox.width > 0 && viewBox.height > 0) {
    return { width: viewBox.width, height: viewBox.height };
  }
  const bounds = svg.getBBox();
  return { width: Math.max(bounds.width, 1), height: Math.max(bounds.height, 1) };
}

function fitDiagram(svg, mode) {
  const sourceSize = dimensions(svg);
  const availableWidth = Math.max(document.documentElement.clientWidth - 24, 1);
  const availableHeight = mode === "fullscreen"
    ? Math.max(document.documentElement.clientHeight - 24, 1)
    : 420;
  const scale = Math.min(1, availableWidth / sourceSize.width, availableHeight / sourceSize.height);
  const width = Math.max(Math.floor(sourceSize.width * scale), 1);
  const height = Math.max(Math.floor(sourceSize.height * scale), 1);
  svg.setAttribute("preserveAspectRatio", "xMidYMid meet");
  svg.style.width = `${width}px`;
  svg.style.height = `${height}px`;
  svg.style.maxWidth = "none";
  return { width, height, scale };
}

async function renderDiagram(source, requestID, theme, mode) {
  newestRequest = requestID;
  const diagram = document.getElementById("diagram");
  diagram.replaceChildren();
  document.body.dataset.mode = mode;
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
    const fitted = svg ? fitDiagram(svg, mode) : { width: 1, height: 1, scale: 1 };
    diagram.style.height = mode === "fullscreen" ? "100%" : `${fitted.height + 24}px`;
    await new Promise(requestAnimationFrame);
    window.webkit.messageHandlers.mermaid.postMessage({
      status: "rendered", requestID, height: fitted.height + 24,
      width: fitted.width, scale: fitted.scale
    });
    return true;
  } catch (error) {
    if (requestID !== newestRequest) return false;
    diagram.replaceChildren();
    window.webkit.messageHandlers.mermaid.postMessage({ status: "error", requestID });
    return false;
  }
}
