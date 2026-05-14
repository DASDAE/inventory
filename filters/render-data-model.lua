local needs_runtime = false

local function stringify(value)
  if value == nil then
    return ""
  end
  return pandoc.utils.stringify(value)
end

local function read_file(path)
  local file = io.open(path, "r")
  if file == nil then
    error("Could not read data model spec: " .. path)
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function parse_yaml(path)
  local content = read_file(path)
  return pandoc.read("---\n" .. content .. "\n---\n", "markdown").meta
end

local function escape_html(value)
  return tostring(value)
    :gsub("&", "&amp;")
    :gsub("<", "&lt;")
    :gsub(">", "&gt;")
end

local function escape_mermaid(value)
  return tostring(value):gsub("\\", "\\\\"):gsub('"', '\\"')
end

local function json_escape(value)
  return tostring(value)
    :gsub("\\", "\\\\")
    :gsub('"', '\\"')
    :gsub("\n", "\\n")
    :gsub("\r", "\\r")
    :gsub("\t", "\\t")
end

local function is_array(table_value)
  if type(table_value) ~= "table" then
    return false
  end
  local count = 0
  for key, _ in pairs(table_value) do
    if type(key) ~= "number" then
      return false
    end
    count = count + 1
  end
  return count == #table_value
end

local function json_encode(value)
  if type(value) == "string" then
    return '"' .. json_escape(value) .. '"'
  elseif type(value) == "number" or type(value) == "boolean" then
    return tostring(value)
  elseif type(value) == "table" then
    local parts = {}
    if is_array(value) then
      for _, item in ipairs(value) do
        table.insert(parts, json_encode(item))
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    for key, item in pairs(value) do
      table.insert(parts, json_encode(tostring(key)) .. ":" .. json_encode(item))
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

local function attr_map(attr)
  return {
    name = stringify(attr.name),
    type = stringify(attr.type),
    description = stringify(attr.description),
  }
end

local function attrs_from_meta(attrs)
  local out = {}
  if attrs == nil then
    return out
  end

  if attrs[1] ~= nil then
    for _, attr in ipairs(attrs) do
      table.insert(out, attr_map(attr))
    end
    return out
  end

  local names = {}
  for name, _ in pairs(attrs) do
    table.insert(names, name)
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local attr = attrs[name]
    table.insert(out, {
      name = name,
      type = stringify(attr.type),
      description = stringify(attr.description),
    })
  end
  return out
end

local function edge_from_meta(edge)
  if edge.from ~= nil then
    return stringify(edge.from), stringify(edge.to), stringify(edge.label)
  end
  return stringify(edge[1]), stringify(edge[2]), stringify(edge[3])
end

local function node_ids(nodes)
  local ids = {}
  for id, _ in pairs(nodes) do
    table.insert(ids, id)
  end
  table.sort(ids)
  return ids
end

local function node_title(node, id)
  return stringify(node.label or id)
end

local function node_display_label(node, id)
  return stringify(node.display or node.alias or node.label or id)
end

local function node_style_attributes(node)
  local style = node.style or {}
  local attrs = {}
  local attr_names = {
    { "fill", "fill" },
    { "stroke", "stroke" },
    { "color", "color" },
    { "stroke_width", "stroke-width" },
  }

  for _, pair in ipairs(attr_names) do
    local spec_name, mermaid_name = pair[1], pair[2]
    local value = stringify(style[spec_name] or node[spec_name])
    if value ~= "" then
      table.insert(attrs, mermaid_name .. ":" .. value)
    end
  end

  return attrs
end

local function style_value(item, name)
  local style = item.style or {}
  return stringify(style[name] or item[name])
end

local function build_mermaid(spec)
  local lines = { "flowchart " .. stringify(spec.direction or "TB") }
  for _, id in ipairs(node_ids(spec.nodes)) do
    local node = spec.nodes[id]
    local label = node_display_label(node, id)
    table.insert(lines, string.format('  %s["%s"]', id, escape_mermaid(label)))
  end

  for _, id in ipairs(node_ids(spec.nodes)) do
    local attrs = node_style_attributes(spec.nodes[id])
    if #attrs > 0 then
      table.insert(lines, string.format("  style %s %s", id, table.concat(attrs, ",")))
    end
  end

  for _, edge in ipairs(spec.edges or {}) do
    local from, to, label = edge_from_meta(edge)
    if label ~= "" then
      table.insert(lines, string.format('  %s -->|"%s"| %s', from, escape_mermaid(label), to))
    else
      table.insert(lines, string.format("  %s --> %s", from, to))
    end
  end

  local reference_label = stringify(spec.reference_label or "references")
  for _, edge in ipairs(spec.references or {}) do
    local from, to, label = edge_from_meta(edge)
    if label == "" then
      label = reference_label
    end
    table.insert(lines, string.format('  %s -. "%s" .-> %s', from, escape_mermaid(label), to))
  end

  return table.concat(lines, "\n")
end

local function build_legend(spec)
  if spec.legend == nil then
    return ""
  end

  local items = {}
  for _, item in ipairs(spec.legend) do
    local label = stringify(item.label)
    if label ~= "" then
      local fill = style_value(item, "fill")
      local stroke = style_value(item, "stroke")
      local color = style_value(item, "color")
      local description = stringify(item.description)
      local swatch_style = {}
      if fill ~= "" then
        table.insert(swatch_style, "background:" .. fill)
      end
      if stroke ~= "" then
        table.insert(swatch_style, "border-color:" .. stroke)
      end
      local label_style = ""
      if color ~= "" then
        label_style = string.format(' style="color:%s"', escape_html(color))
      end
      local body = string.format(
        '<span class="data-model-legend-swatch" style="%s"></span><span class="data-model-legend-label"%s>%s</span>',
        escape_html(table.concat(swatch_style, ";")),
        label_style,
        escape_html(label)
      )
      if description ~= "" then
        body = body .. string.format('<span class="data-model-legend-description">%s</span>', escape_html(description))
      end
      table.insert(items, '<li class="data-model-legend-item">' .. body .. '</li>')
    end
  end

  if #items == 0 then
    return ""
  end

  return '<div class="data-model-legend" aria-label="Data model color legend"><div class="data-model-legend-title">Legend</div><ul>' ..
    table.concat(items, "\n") ..
    '</ul></div>'
end

local function build_docs(spec)
  local docs = {}
  for id, node in pairs(spec.nodes) do
    local title = node_title(node, id)
    local display = node_display_label(node, id)
    docs[display] = {
      title = title,
      display = display,
      summary = stringify(node.summary),
      attributes = attrs_from_meta(node.attributes),
    }
  end
  return docs
end

local function runtime_script()
  return [[
<script>
(function () {
  function ensureTooltip() {
    let tooltip = document.querySelector(".data-model-tooltip");
    if (!tooltip) {
      tooltip = document.createElement("div");
      tooltip.className = "data-model-tooltip";
      tooltip.setAttribute("role", "tooltip");
      document.body.appendChild(tooltip);
    }
    return tooltip;
  }

  function appendText(parent, className, text) {
    const node = document.createElement("div");
    node.className = className;
    node.textContent = text;
    parent.appendChild(node);
  }

  function renderTooltip(tooltip, doc) {
    tooltip.replaceChildren();
    appendText(tooltip, "data-model-tooltip-title", doc.title);
    appendText(tooltip, "data-model-tooltip-heading", "Summary");
    appendText(tooltip, "data-model-tooltip-rule", "-------");
    appendText(tooltip, "data-model-tooltip-summary", doc.summary || "");
    appendText(tooltip, "data-model-tooltip-heading", "Attributes");
    appendText(tooltip, "data-model-tooltip-rule", "----------");

    for (const attr of doc.attributes || []) {
      const item = document.createElement("div");
      item.className = "data-model-tooltip-attribute";

      const signature = document.createElement("div");
      signature.className = "data-model-tooltip-signature";
      const name = document.createElement("strong");
      name.textContent = attr.name || "";
      signature.appendChild(name);
      signature.appendChild(document.createTextNode(" : " + (attr.type || "")));

      const description = document.createElement("div");
      description.className = "data-model-tooltip-description";
      description.textContent = attr.description || "";

      item.appendChild(signature);
      item.appendChild(description);
      tooltip.appendChild(item);
    }
  }

  function positionTooltip(tooltip, event) {
    const margin = 16;
    let left = event.clientX + margin;
    let top = event.clientY + margin;
    const rect = tooltip.getBoundingClientRect();
    if (left + rect.width > window.innerWidth - margin) {
      left = event.clientX - rect.width - margin;
    }
    if (top + rect.height > window.innerHeight - margin) {
      top = window.innerHeight - rect.height - margin;
    }
    tooltip.style.left = Math.max(margin, left) + "px";
    tooltip.style.top = Math.max(margin, top) + "px";
  }

  function attachTooltips(container, docs) {
    const tooltip = ensureTooltip();
    container.querySelectorAll("svg g.node").forEach((node) => {
      const label = node.textContent.replace(/\s+/g, " ").trim();
      const doc = docs[label];
      if (!doc || node.dataset.dataModelTooltipAttached) {
        return;
      }
      node.dataset.dataModelTooltipAttached = "true";
      node.style.cursor = "help";
      node.addEventListener("mouseenter", (event) => {
        renderTooltip(tooltip, doc);
        tooltip.classList.add("is-visible");
        positionTooltip(tooltip, event);
      });
      node.addEventListener("mousemove", (event) => positionTooltip(tooltip, event));
      node.addEventListener("mouseleave", () => tooltip.classList.remove("is-visible"));
    });
  }

  async function renderDataModels() {
    if (!window.mermaid) {
      window.setTimeout(renderDataModels, 100);
      return;
    }
    window.mermaid.initialize({ startOnLoad: false });
    const blocks = document.querySelectorAll(".render-data-model-mermaid:not([data-processed])");
    let index = 0;
    for (const block of blocks) {
      block.dataset.processed = "true";
      const container = block.closest(".render-data-model");
      const docs = JSON.parse(container.querySelector("script[type='application/json']").textContent);
      const graph = block.textContent.replaceAll("&nbsp;", " ");
      const id = "render-data-model-" + (++index);
      const result = await window.mermaid.mermaidAPI.render(id, graph, block);
      const wrapper = document.createElement("div");
      wrapper.className = "render-data-model-svg";
      wrapper.innerHTML = result.svg;
      block.replaceWith(wrapper);
      attachTooltips(container, docs);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", renderDataModels);
  } else {
    renderDataModels();
  }
})();
</script>
]]
end

function Div(el)
  if not el.classes:includes("render_data_model") then
    return nil
  end

  local spec_path = el.attributes.spec
  if spec_path == nil or spec_path == "" then
    error("render_data_model requires a spec attribute")
  end

  needs_runtime = true
  local spec = parse_yaml(spec_path)
  local mermaid = build_mermaid(spec)
  local legend = build_legend(spec)
  local docs = build_docs(spec)
  local html = string.format(
    '<div class="render-data-model" data-model-id="%s">\n<pre class="render-data-model-mermaid">%s</pre>\n%s\n<script type="application/json" class="render-data-model-docs">%s</script>\n</div>',
    escape_html(stringify(spec.id or spec_path)),
    escape_html(mermaid),
    legend,
    escape_html(json_encode(docs))
  )
  return pandoc.RawBlock("html", html)
end

function Pandoc(doc)
  if needs_runtime then
    quarto.doc.add_html_dependency({
      name = "render-data-model-mermaid",
      scripts = { "/opt/quarto/share/formats/html/mermaid/mermaid.min.js" },
    })
    doc.blocks:insert(pandoc.RawBlock("html", runtime_script()))
  end
  return doc
end
