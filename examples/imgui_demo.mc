import sokol_all;
import imgui;
import sokol_imgui;

// sokol_imgui demo

// this demo shows a sub-set of the original C++ widget demo


const i32 WINDOW_W = 1024;
const i32 WINDOW_H = 720;


// Persistent widget state
private {
    bool g_checked = true;
    f32  g_slider = 0.5f;
    i32  g_clicks = 0;
    i32  g_radio = 0;
    i32  g_slider_i = 3;
    f32  g_drag = 1.0f;
    i32  g_combo = 0;
    u8[128] g_text;
    f32[4] g_color;
    i32  g_listbox = 0;
    f32[7] g_frame_times;
    i32  g_input_int = 5;
    f32  g_input_float = 1.5f;
    f32  g_angle = 0.5f;
    i32  g_drag_int = 20;
    i32  g_dnd_received = 0;
    f32[3] g_vec3;
    i32[2] g_vec2i;
    f64  g_dbl = 3.14159;
    u8[256] g_multiline;
    u8[64] g_hint;
    f32[3] g_col3;
    f32[4] g_pick;
    f32  g_vslider = 0.5f;
    i32  g_status_clicks = 0;
    bool[5] g_selected;
    f32  g_progress = 0.0f;
    f32  g_slider_log = 0.5f;
    bool g_show_metrics = false;
    // "Window options" toggles
    bool g_no_titlebar = false;
    bool g_no_scrollbar = false;
    bool g_no_menu = false;
    bool g_no_move = false;
    bool g_no_resize = false;
    bool g_no_collapse = false;
    bool g_no_nav = false;
    bool g_no_background = false;
    bool g_no_front = false;
    // animated cosine plot
    f32[90] g_anim;
    i32  g_anim_off = 0;
    f32  g_anim_phase = 0.0f;
    bool g_animate = true;
    f64  g_refresh_time = 0.0;
}


void imgui_init() {
    sg_setup(&sg_desc{ .environment = sglue_environment() });
    simgui_setup(&simgui_desc_t{});
    ignore strcpy(g_text, "type here");
    g_color[0] = 0.4f; g_color[1] = 0.7f; g_color[2] = 0.95f; g_color[3] = 1.0f;
    g_vec3[0] = 0.1f; g_vec3[1] = 0.2f; g_vec3[2] = 0.3f;
    g_vec2i[0] = 1; g_vec2i[1] = 2;
    g_col3[0] = 0.2f; g_col3[1] = 0.5f; g_col3[2] = 0.8f;
    g_pick[0] = 0.3f; g_pick[1] = 0.6f; g_pick[2] = 0.9f; g_pick[3] = 1.0f;
    ignore strcpy(g_multiline, "multi-line\ntext editor");
    g_hint[0] = 0;
    // The original demo's static "Frame Times" / "Histogram" sample array.
    g_frame_times[0] = 0.6f; g_frame_times[1] = 0.1f; g_frame_times[2] = 1.0f;
    g_frame_times[3] = 0.5f; g_frame_times[4] = 0.92f; g_frame_times[5] = 0.1f;
    g_frame_times[6] = 0.2f;
}


void imgui_frame() {
    simgui_new_frame(&simgui_frame_desc_t{
        .width = sapp_width(),
        .height = sapp_height(),
        .delta_time = sapp_frame_duration(),
        .dpi_scale = sapp_dpi_scale(),
    });

    // mirror Dear ImGui's ShowDemoWindow()
    ImGuiWindowFlags wflags = cast(ImGuiWindowFlags, 0);
    if !g_no_menu       { wflags = wflags | ImGuiWindowFlags_MenuBar; }
    if g_no_titlebar    { wflags = wflags | ImGuiWindowFlags_NoTitleBar; }
    if g_no_scrollbar   { wflags = wflags | ImGuiWindowFlags_NoScrollbar; }
    if g_no_move        { wflags = wflags | ImGuiWindowFlags_NoMove; }
    if g_no_resize      { wflags = wflags | ImGuiWindowFlags_NoResize; }
    if g_no_collapse    { wflags = wflags | ImGuiWindowFlags_NoCollapse; }
    if g_no_nav         { wflags = wflags | ImGuiWindowFlags_NoNav; }
    if g_no_background  { wflags = wflags | ImGuiWindowFlags_NoBackground; }
    if g_no_front       { wflags = wflags | ImGuiWindowFlags_NoBringToFrontOnFocus; }
    ImGui_SetNextWindowSize(ImVec2{550.0f, 680.0f}, ImGuiCond_FirstUseEver);
    if ImGui_Begin("Dear ImGui Demo", null, wflags) {
        // --- Menu bar: Menu / Examples / Tools ---
        if ImGui_BeginMenuBar() {
            if ImGui_BeginMenu("Menu", true) {
                ignore ImGui_MenuItem("New", null, false, true);
                ignore ImGui_MenuItem("Open", "Ctrl+O", false, true);
                ignore ImGui_MenuItem("Save", "Ctrl+S", false, true);
                ImGui_Separator();
                ignore ImGui_MenuItem("Quit", "Alt+F4", false, true);
                ImGui_EndMenu();
            }
            if ImGui_BeginMenu("Examples", true) {
                ImGui_MenuItem("Main menu bar", null, &g_checked, true);
                ImGui_EndMenu();
            }
            if ImGui_BeginMenu("Tools", true) {
                ImGui_MenuItem("Metrics/Debugger", null, &g_show_metrics, true);
                ignore ImGui_MenuItem("About minc imgui", null, false, true);
                ImGui_EndMenu();
            }
            ImGui_EndMenuBar();
        }

        ImGui_Text("dear imgui says hello! (minc native port)");
        ImGui_Spacing();

        if ImGui_CollapsingHeader("Help", 0) {
            ImGui_SeparatorText("ABOUT THIS DEMO:");
            ImGui_BulletText("This panel mirrors Dear ImGui's ShowDemoWindow layout,");
            ImGui_BulletText("rendered from minc's native imgui transpile.");
        }

        if ImGui_CollapsingHeader("Configuration", 0) {
            var io = ImGui_GetIO();
            ImGui_Text("Dear ImGui — minc native port");
            ImGui_Text("%.3f ms/frame (%.1f FPS)", 1000.0f / io.Framerate, io.Framerate);
            ImGui_SeparatorText("Flags");
            ImGui_Text("io.ConfigFlags = 0x%08X", cast(i32, io.ConfigFlags));
            ImGui_Checkbox("a config checkbox", &g_checked);
        }

        if ImGui_CollapsingHeader("Window options", 0) {
            ImGui_Checkbox("No titlebar", &g_no_titlebar);      ImGui_SameLine(150.0f, -1.0f);
            ImGui_Checkbox("No scrollbar", &g_no_scrollbar);    ImGui_SameLine(300.0f, -1.0f);
            ImGui_Checkbox("No menu", &g_no_menu);
            ImGui_Checkbox("No move", &g_no_move);              ImGui_SameLine(150.0f, -1.0f);
            ImGui_Checkbox("No resize", &g_no_resize);          ImGui_SameLine(300.0f, -1.0f);
            ImGui_Checkbox("No collapse", &g_no_collapse);
            ImGui_Checkbox("No nav", &g_no_nav);                ImGui_SameLine(150.0f, -1.0f);
            ImGui_Checkbox("No background", &g_no_background);   ImGui_SameLine(300.0f, -1.0f);
            ImGui_Checkbox("No bring to front", &g_no_front);
        }

        if ImGui_CollapsingHeader("Widgets", 0) {
            if ImGui_TreeNode("Basic") {
                if ImGui_Button("Button", ImVec2{0.0f, 0.0f}) { g_clicks = g_clicks + 1; }
                ImGui_SameLine(0.0f, -1.0f);
                ImGui_Text("clicks: %d", g_clicks);
                if ImGui_SmallButton("Small Button") { g_clicks = g_clicks + 1; }
                ImGui_SameLine(0.0f, -1.0f);
                ignore ImGui_ArrowButton("##left", ImGuiDir_Left);
                ImGui_SameLine(0.0f, -1.0f);
                ignore ImGui_ArrowButton("##right", ImGuiDir_Right);
                ImGui_Checkbox("checkbox", &g_checked);
                ImGui_RadioButton("radio a", &g_radio, 0); ImGui_SameLine(0.0f, -1.0f);
                ImGui_RadioButton("radio b", &g_radio, 1); ImGui_SameLine(0.0f, -1.0f);
                ImGui_RadioButton("radio c", &g_radio, 2);
                u8*[3] combo_items = {"alpha", "beta", "gamma"};
                ImGui_Combo("combo", &g_combo, combo_items, 3, -1);
                ImGui_SliderFloat("slider float", &g_slider, 0.0f, 1.0f, null, 0);
                ImGui_SliderInt("slider int", &g_slider_i, 0, 10, null, 0);
                ImGui_DragFloat("drag float", &g_drag, 0.1f, 0.0f, 0.0f, null, 0);
                ImGui_PushStyleVar(ImGuiStyleVar_FrameRounding, 6.0f);
                ImGui_Button("rounded button", ImVec2{0.0f, 0.0f});
                ImGui_PopStyleVar(1);
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Tooltips") {
                ImGui_Button("Hover me", ImVec2{0.0f, 0.0f});
                if ImGui_IsItemHovered(0) {
                    if ImGui_BeginTooltip() {
                        ImGui_TextUnformatted("I am a transpiled tooltip", null);
                        ImGui_EndTooltip();
                    }
                }
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Tree Nodes") {
                if ImGui_TreeNode("tree root") {
                    if ImGui_TreeNode("branch") {
                        ImGui_TextUnformatted("leaf", null);
                        ImGui_TreePop();
                    }
                    ImGui_TextUnformatted("sibling", null);
                    ImGui_TreePop();
                }
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Collapsing Headers") {
                if ImGui_CollapsingHeader("a nested collapsing header", 0) {
                    ImGui_TextUnformatted("content under the header", null);
                }
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Bullets") {
                ImGui_BulletText("Bullet point 1");
                ImGui_BulletText("Bullet point 2");
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Text") {
                ImGui_TextColored(ImVec4{1.0f, 0.6f, 0.2f, 1.0f}, "colored text");
                ImGui_TextDisabled("disabled text");
                ImGui_TextWrapped("wrapped text that is long enough to wrap inside the window width when the panel is narrow");
                ImGui_LabelText("label", "value %d", 3);
                ImGui_SeparatorText("a separator with text");
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Images") {
                // Draw the font atlas texture
                var io = ImGui_GetIO();
                if io.Fonts != null && io.Fonts.TexData != null {
                    ImTextureRef tex = io.Fonts.TexRef;
                    f32 tw = cast(f32, io.Fonts.TexData.Width);
                    f32 th = cast(f32, io.Fonts.TexData.Height);
                    ImGui_Text("Font atlas texture: %.0fx%.0f", tw, th);
                    ImGui_Image(tex, ImVec2{tw, th}, ImVec2{0.0f, 0.0f}, ImVec2{1.0f, 1.0f});
                }
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Combo") {
                u8*[5] combo2_items = {"AAAA", "BBBB", "CCCC", "DDDD", "EEEE"};
                if ImGui_BeginCombo("combo", combo2_items[g_combo], 0) {
                    for i32 n = 0; n < 5; n++ {
                        bool is_sel = g_combo == n;
                        if ImGui_Selectable(combo2_items[n], is_sel, 0, ImVec2{0.0f, 0.0f}) { g_combo = n; }
                    }
                    ImGui_EndCombo();
                }
                ImGui_TreePop();
            }
            if ImGui_TreeNode("List boxes") {
                u8*[4] list_items = {"item one", "item two", "item three", "item four"};
                ImGui_ListBox("listbox", &g_listbox, list_items, 4, 4);
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Selectables") {
                if ImGui_Selectable("1. I am selectable", g_selected[0], 0, ImVec2{0.0f, 0.0f}) { g_selected[0] = !g_selected[0]; }
                if ImGui_Selectable("2. I am selectable", g_selected[1], 0, ImVec2{0.0f, 0.0f}) { g_selected[1] = !g_selected[1]; }
                if ImGui_Selectable("3. I am selectable", g_selected[2], 0, ImVec2{0.0f, 0.0f}) { g_selected[2] = !g_selected[2]; }
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Text Input") {
                ImGui_InputText("input text", g_text, 128, 0, null, null);
                ImGui_InputTextMultiline("multiline", g_multiline, 256, ImVec2{0.0f, 60.0f}, 0, null, null);
                ImGui_InputTextWithHint("with hint", "type here...", g_hint, 64, 0, null, null);
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Tabs") {
                if ImGui_BeginTabBar("tabs", 0) {
                    if ImGui_BeginTabItem("first", null, 0) {
                        if ImGui_BeginChild("first_scroll", ImVec2{0.0f, 80.0f}, ImGuiChildFlags_Borders, 0) {
                            for i32 row = 0; row < 20; row++ { ImGui_Text("first row %d", row); }
                        }
                        ImGui_EndChild();
                        ImGui_EndTabItem();
                    }
                    if ImGui_BeginTabItem("second", null, 0) {
                        if ImGui_BeginChild("second_scroll", ImVec2{0.0f, 80.0f}, ImGuiChildFlags_Borders, 0) {
                            for i32 row = 0; row < 20; row++ { ImGui_Text("second row %d", row); }
                        }
                        ImGui_EndChild();
                        ImGui_EndTabItem();
                    }
                    ImGui_EndTabBar();
                }
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Plotting") {
                ImGui_Checkbox("Animate", &g_animate);
                ImGui_PlotLines("Frame Times", g_frame_times, 7, 0, null, FLT_MAX, FLT_MAX, ImVec2{0.0f, 0.0f}, 4);
                ImGui_PlotHistogram("Histogram", g_frame_times, 7, 0, null, 0.0f, 1.0f, ImVec2{0.0f, 80.0f}, 4);
                // Fill a contiguous array at a fixed 60 Hz
                if !g_animate || g_refresh_time == 0.0 { g_refresh_time = ImGui_GetTime(); }
                while g_refresh_time < ImGui_GetTime() {
                    g_anim[g_anim_off] = cosf(g_anim_phase);
                    g_anim_off = (g_anim_off + 1) % 90;
                    g_anim_phase = g_anim_phase + 0.1f * cast(f32, g_anim_off);
                    g_refresh_time = g_refresh_time + 1.0 / 60.0;
                }
                f32 average = 0.0f;
                for i32 n = 0; n < 90; n++ { average = average + g_anim[n]; }
                average = average / 90.0f;
                u8[32] overlay;
                ignore snprintf(overlay, cast(u64, 32), "avg %f", average);
                ImGui_PlotLines("Lines", g_anim, 90, g_anim_off, overlay, -1.0f, 1.0f, ImVec2{0.0f, 80.0f}, 4);
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Progress Bars") {
                g_progress = g_progress + 0.004f;
                if g_progress > 1.0f { g_progress = 0.0f; }
                ImGui_ProgressBar(g_progress, ImVec2{0.0f, 0.0f}, null);
                ImGui_ProgressBar(g_progress, ImVec2{0.0f, 0.0f}, "loading...");
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Color/Picker Widgets") {
                ImGui_ColorEdit3("color 1", g_col3, 0);
                ImGui_ColorEdit4("color 2", g_color, 0);
                ignore ImGui_ColorButton("swatch", ImVec4{g_col3[0], g_col3[1], g_col3[2], 1.0f}, 0, ImVec2{0.0f, 0.0f});
                ImGui_ColorPicker4("picker", g_pick, 0, null);
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Drag and Slider Flags") {
                ImGui_DragFloat("drag (AlwaysClamp)", &g_drag, 0.1f, 0.0f, 1.0f, null, ImGuiSliderFlags_AlwaysClamp);
                ImGui_SliderFloat("slider (Logarithmic)", &g_slider_log, 0.001f, 10.0f, "%.4f", ImGuiSliderFlags_Logarithmic);
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Data Types") {
                ImGui_InputInt("input int", &g_input_int, 1, 10, 0);
                ImGui_InputFloat("input float", &g_input_float, 0.1f, 1.0f, "%.3f", 0);
                ImGui_InputDouble("input double", &g_dbl, 0.1, 1.0, "%.5f", 0);
                ImGui_SliderAngle("slider angle", &g_angle, -360.0f, 360.0f, "%.0f deg", 0);
                ImGui_DragInt("drag int", &g_drag_int, 1.0f, 0, 100, "%d", 0);
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Multi-component Widgets") {
                ImGui_SliderFloat3("slider float3", g_vec3, 0.0f, 1.0f, null, 0);
                ImGui_DragFloat3("drag float3", g_vec3, 0.01f, 0.0f, 0.0f, null, 0);
                ImGui_InputFloat3("input float3", g_vec3, null, 0);
                ImGui_SliderInt2("slider int2", g_vec2i, 0, 10, null, 0);
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Vertical Sliders") {
                ImGui_VSliderFloat("##v", ImVec2{20.0f, 80.0f}, &g_vslider, 0.0f, 1.0f, null, 0);
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Drag and Drop") {
                ImGui_Button("Drag source", ImVec2{0.0f, 0.0f});
                if ImGui_BeginDragDropSource(0) {
                    i32 payload = 7;
                    ignore ImGui_SetDragDropPayload("DEMO_INT", &payload, sizeof(i32), 0);
                    ImGui_TextUnformatted("dragging 7", null);
                    ImGui_EndDragDropSource();
                }
                ImGui_SameLine(0.0f, -1.0f);
                ImGui_Text("Drop target (got %d)", g_dnd_received);
                if ImGui_BeginDragDropTarget() {
                    ImGuiPayload* p = ImGui_AcceptDragDropPayload("DEMO_INT", 0);
                    if p != null { g_dnd_received = *cast(i32*, p.Data); }
                    ImGui_EndDragDropTarget();
                }
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Querying Item Status") {
                if ImGui_Button("status button", ImVec2{0.0f, 0.0f}) { g_status_clicks = g_status_clicks + 1; }
                ImGui_Text("active=%d clicks=%d", cast(i32, ImGui_IsItemActive()), g_status_clicks);
                for i32 i = 0; i < 4; i++ {
                    ImGui_PushID(i);
                    if ImGui_SmallButton("dup") { g_clicks = g_clicks + 1; }
                    ImGui_SameLine(0.0f, -1.0f);
                    ImGui_PopID();
                }
                ImGui_NewLine();
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Querying Window Status") {
                ImGui_Text("IsWindowFocused() = %d", cast(i32, ImGui_IsWindowFocused(0)));
                ImGui_Text("IsWindowHovered() = %d", cast(i32, ImGui_IsWindowHovered(0)));
                ImGui_TreePop();
            }
        }

        if ImGui_CollapsingHeader("Layout & Scrolling", 0) {
            if ImGui_TreeNode("Indent / Group") {
                ImGui_Indent(0.0f);
                ImGui_TextUnformatted("indented line", null);
                ImGui_Unindent(0.0f);
                ImGui_BeginGroup();
                ImGui_TextUnformatted("grouped A", null);
                ImGui_TextUnformatted("grouped B", null);
                ImGui_EndGroup();
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Columns") {
                ImGui_Columns(2, "cols", true);
                ImGui_TextUnformatted("left column", null); ImGui_NextColumn();
                ImGui_TextUnformatted("right column", null); ImGui_NextColumn();
                ImGui_Columns(1, null, false);
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Disabled") {
                ImGui_BeginDisabled(true);
                ImGui_Button("disabled button", ImVec2{0.0f, 0.0f});
                ImGui_EndDisabled();
                ImGui_TreePop();
            }
        }

        if ImGui_CollapsingHeader("Popups & Modal windows", 0) {
            if ImGui_TreeNode("Popups") {
                ImGui_Button("right-click me", ImVec2{0.0f, 0.0f});
                if ImGui_BeginPopupContextItem("ctx", 1) {
                    if ImGui_Selectable("a context action", false, 0, ImVec2{0.0f, 0.0f}) { g_clicks = g_clicks + 1; }
                    ImGui_EndPopup();
                }
                ImGui_TreePop();
            }
            if ImGui_TreeNode("Modals") {
                if ImGui_Button("Open Modal", ImVec2{0.0f, 0.0f}) { ImGui_OpenPopup("Delete?", 0); }
                if ImGui_BeginPopupModal("Delete?", null, 0) {
                    ImGui_TextUnformatted("This is a modal popup.", null);
                    if ImGui_Button("OK", ImVec2{0.0f, 0.0f}) { ImGui_CloseCurrentPopup(); }
                    ImGui_EndPopup();
                }
                ImGui_TreePop();
            }
        }

        if ImGui_CollapsingHeader("Tables & Columns", 0) {
            if ImGui_BeginTable("table", 2, 0, ImVec2{0.0f, 0.0f}, 0.0f) {
                ImGui_TableSetupColumn("name", 0, 0.0f, 0);
                ImGui_TableSetupColumn("value", 0, 0.0f, 0);
                ImGui_TableHeadersRow();
                ImGui_TableNextRow(0, 0.0f);
                ImGui_TableNextColumn();
                ImGui_TextUnformatted("slider float", null);
                ImGui_TableNextColumn();
                ImGui_Text("%.3f", g_slider);
                ImGui_EndTable();
            }
        }

        if ImGui_CollapsingHeader("Inputs & Focus", 0) {
            var io = ImGui_GetIO();
            ImGui_Text("Mouse pos: (%.1f, %.1f)", io.MousePos.x, io.MousePos.y);
            ImGui_Text("Mouse left down: %d", cast(i32, ImGui_IsMouseDown(ImGuiMouseButton_Left)));
            ImGui_Text("KeyCtrl: %d", cast(i32, io.KeyCtrl));
            ImGui_Text("Space down: %d", cast(i32, ImGui_IsKeyDown(ImGuiKey_Space)));
        }
    }
    ImGui_End();

    // Tools ▸ Metrics/Debugger — the real ImGui::ShowMetricsWindow
    if g_show_metrics { ImGui_ShowMetricsWindow(&g_show_metrics); }

    sg_begin_pass(&sg_pass{
        .action.colors[0].load_action = SG_LOADACTION_CLEAR,
        .action.colors[0].clear_value = sg_color{ 0.39f, 0.58f, 0.93f, 1.0f },
        .swapchain = sglue_swapchain(),
    });
    simgui_render();
    sg_end_pass();
    sg_commit();
}


void imgui_event(sapp_event* ev) {
    ignore simgui_handle_event(ev);
}


void imgui_cleanup() {
    simgui_shutdown();
    sg_shutdown();
}


sapp_desc sokol_main() {
    return sapp_desc{
        .init_cb = imgui_init,
        .frame_cb = imgui_frame,
        .event_cb = imgui_event,
        .cleanup_cb = imgui_cleanup,
        .width = WINDOW_W,
        .height = WINDOW_H,
        .high_dpi = true,
        .window_title = "Dear ImGui Demo (minc)",
    };
}
