local needs_runtime = false
local reference_spec_path = "specs/dasdae-inventory.yml"
local reference_links = nil

local function stringify(value)
  if value == nil then
    return ""
  end
  return pandoc.utils.stringify(value)
end

local function read_file(path)
  local file = io.open(path, "r")
  if file == nil then
    file = io.open("../" .. path, "r")
  end
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
  local name = stringify(attr.name)
  local description = stringify(attr.description)
  if name == "" and description:match("Dynamic coordinate field named by CoordinateReferenceSystem%.coordinate_labels") then
    name = "<coordinate_label>"
  end
  return {
    name = name,
    type = stringify(attr.type),
    description = description,
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

local function page_name(name, extension)
  local cleaned = tostring(name):gsub("[^A-Za-z0-9_.-]", "")
  return cleaned .. (extension or ".qmd")
end

local function current_doc_depth()
  local input = ""
  if quarto ~= nil and quarto.doc ~= nil and quarto.doc.input_file ~= nil then
    input = tostring(quarto.doc.input_file)
  elseif PANDOC_STATE.input_files and PANDOC_STATE.input_files[1] then
    input = PANDOC_STATE.input_files[1]
  end
  input = input:gsub("\\", "/")
  local matched_project_relative = false
  for _, top_dir in ipairs({ "API", "Intro", "Model", "Scenarios", "Examples", "References" }) do
    local project_relative = input:match("(" .. top_dir .. "/[^/]+%.qmd)$")
    if project_relative ~= nil then
      input = project_relative
      matched_project_relative = true
      break
    end
  end
  if not matched_project_relative and (input:match("/index%.qmd$") or input == "index.qmd") then
    input = "index.qmd"
  end
  input = input:gsub("^%./", "")
  local directory = input:match("^(.*)/[^/]*$")
  if directory ~= nil then
    directory = directory:gsub("^%./", "")
  end
  if directory == nil or directory == "" or directory == "." then
    return 0
  end
  local depth = 0
  for _ in directory:gmatch("[^/]+") do
    depth = depth + 1
  end
  return depth
end

local function reference_href(name, extension)
  local prefix = string.rep("../", current_doc_depth())
  return prefix .. "References/" .. page_name(name, extension)
end

local function graph_reference_href(spec, node, id)
  if stringify(spec.id) ~= "dasdae-inventory" then
    return ""
  end
  local title = node_title(node, id)
  if title == "" then
    return ""
  end
  return reference_href(title, ".html")
end

local function reference_class_links()
  if reference_links ~= nil then
    return reference_links
  end

  reference_links = {}
  local spec = parse_yaml(reference_spec_path)
  for id, node in pairs(spec.nodes or {}) do
    local name = node_title(node, id)
    if name ~= "" then
      reference_links[name] = name
      local node_id = stringify(id)
      if node_id ~= "" then
        reference_links[node_id] = name
      end
      local display = stringify(node.display or node.alias)
      if display ~= "" then
        reference_links[display] = name
      end
    end
  end

  return reference_links
end

function Code(el)
  local target = reference_class_links()[el.text]
  if target == nil then
    return nil
  end
  return pandoc.Link({ pandoc.Code(el.text) }, reference_href(target, ".qmd"))
end

local function style_source_from_spec(spec)
  local style_source = spec.styles or {}
  local style_path = stringify(style_source)
  local is_inline_style_list = type(style_source) == "table" and style_source[1] ~= nil and style_source[1].id ~= nil

  if not is_inline_style_list and style_path ~= "" then
    local parsed = parse_yaml(style_path)
    return parsed.styles or {}
  end

  if is_inline_style_list then
    return style_source
  end

  return {}
end

local function styles_from_spec(spec)
  local style_source = style_source_from_spec(spec)
  local styles = {}
  for _, style in ipairs(style_source) do
    local id = stringify(style.id)
    if id ~= "" then
      styles[id] = style
    end
  end
  return styles
end

local function used_style_classes(spec)
  local used = {}
  for _, node in pairs(spec.nodes or {}) do
    local style_class = stringify(node.style_class or node.class)
    if style_class ~= "" then
      used[style_class] = true
    end
  end
  return used
end

local function resolved_style(item, styles)
  local style_class = stringify(item.style_class or item.class)
  local inherited = styles[style_class] or {}
  local inline = item.style or {}
  local resolved = {}

  for key, value in pairs(inherited) do
    resolved[key] = value
  end
  for key, value in pairs(inline) do
    resolved[key] = value
  end

  return resolved
end

local function style_value(item, name, styles)
  local style = resolved_style(item, styles or {})
  return stringify(style[name] or item[name])
end

local function graph_node_map(spec, styles)
  local nodes = {}
  for _, id in ipairs(node_ids(spec.nodes)) do
    local node = spec.nodes[id]
    local style = resolved_style(node, styles)
    local display = node_display_label(node, id)
    nodes[id] = {
      id = id,
      label = display,
      title = node_title(node, id),
      reference_href = graph_reference_href(spec, node, id),
      summary = stringify(node.summary),
      attributes = attrs_from_meta(node.attributes),
      children = stringify(node.children or "open"),
      style_class = stringify(node.style_class or node.class),
      fill = stringify(style.fill or "#ffffff"),
      stroke = stringify(style.stroke or "#b9c4cc"),
      color = stringify(style.color or "#243036"),
    }
  end
  return nodes
end

local function build_graph(spec)
  local styles = styles_from_spec(spec)
  local nodes = graph_node_map(spec, styles)
  local elements = {}

  for _, id in ipairs(node_ids(spec.nodes)) do
    table.insert(elements, { group = "nodes", data = nodes[id] })
  end

  local edge_index = 0
  for _, edge in ipairs(spec.edges or {}) do
    edge_index = edge_index + 1
    local from, to, label = edge_from_meta(edge)
    table.insert(elements, {
      group = "edges",
      data = {
        id = "edge-" .. tostring(edge_index),
        source = from,
        target = to,
        label = label,
        kind = "containment",
      },
    })
  end

  for _, edge in ipairs(spec.references or {}) do
    edge_index = edge_index + 1
    local from, to, label = edge_from_meta(edge)
    if label == "" then
      label = stringify(spec.reference_label or "references")
    end
    table.insert(elements, {
      group = "edges",
      data = {
        id = "edge-" .. tostring(edge_index),
        source = from,
        target = to,
        label = label,
        kind = "reference",
      },
    })
  end

  return {
    id = stringify(spec.id),
    title = stringify(spec.title),
    direction = stringify(spec.direction or "TB"),
    elements = elements,
  }
end

local function legend_items(spec)
  if spec.legend ~= nil then
    return spec.legend
  end
  local used = used_style_classes(spec)
  local items = {}
  for _, style in ipairs(style_source_from_spec(spec)) do
    local id = stringify(style.id)
    if used[id] then
      table.insert(items, style)
    end
  end
  return items
end

local function build_legend(spec)
  local source_items = legend_items(spec)
  if source_items == nil then
    return ""
  end

  local styles = styles_from_spec(spec)
  local items = {}
  for _, item in ipairs(source_items) do
    local label = stringify(item.label)
    if label ~= "" then
      local fill = style_value(item, "fill", styles)
      local stroke = style_value(item, "stroke", styles)
      local color = style_value(item, "color", styles)
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

local function build_model_title(spec)
  local title = stringify(spec.title)
  if title == "" then
    return ""
  end
  return string.format('<div class="data-model-title">%s</div>', escape_html(title))
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
  local graph = build_graph(spec)
  local title = build_model_title(spec)
  local legend = build_legend(spec)
  local graph_json = json_encode(graph):gsub("</", "<\\/")
  local html = string.format(
    '<div class="render-data-model" data-model-id="%s">\n%s\n<div class="render-data-model-toolbar"><button type="button" data-action="expand">Expand all</button><button type="button" data-action="collapse">Collapse all</button></div>\n<div class="render-data-model-graph" role="img" aria-label="%s"></div>\n%s\n<script type="application/json" class="render-data-model-graph-data">%s</script>\n</div>',
    escape_html(stringify(spec.id or spec_path)),
    title,
    escape_html(stringify(spec.title or spec.id or spec_path)),
    legend,
    graph_json
  )
  return pandoc.RawBlock("html", html)
end

function Pandoc(doc)
  if needs_runtime then
    quarto.doc.add_html_dependency({
      name = "cytoscape",
      version = "3.30.4",
      scripts = { "../vendor/cytoscape/cytoscape.min.js" },
    })
    quarto.doc.add_html_dependency({
      name = "elkjs",
      version = "0.10.0",
      scripts = { "../vendor/elk/elk.bundled.js" },
    })
    quarto.doc.add_html_dependency({
      name = "cytoscape-elk",
      version = "2.2.0",
      scripts = { "../vendor/elk/cytoscape-elk.min.js" },
    })
    quarto.doc.add_html_dependency({
      name = "render-data-model",
      version = "1.0.0",
      scripts = { "../js/render-data-model.js" },
    })
  end
  return doc
end
