import os
import os.path
import re
from typing import List

from nvim_doc_tools import (
    Vimdoc,
    VimdocSection,
    generate_md_toc,
    indent,
    parse_directory,
    read_section,
    render_md_api2,
    render_vimdoc_api2,
    replace_section,
)

HERE = os.path.dirname(__file__)
ROOT = os.path.abspath(os.path.join(HERE, os.path.pardir))
README = os.path.join(ROOT, "README.md")
DOC = os.path.join(ROOT, "doc")
VIMDOC = os.path.join(DOC, "quicker.txt")


def add_md_link_path(path: str, lines: List[str]) -> List[str]:
    ret = []
    for line in lines:
        ret.append(re.sub(r"(\(#)", "(" + path + "#", line))
    return ret


def update_md_api():
    types = parse_directory(os.path.join(ROOT, "lua"))
    funcs = types.files["quicker/init.lua"].functions
    lines = ["\n"] + render_md_api2(funcs, types, 3)[:-1]  # trim last newline
    replace_section(
        README,
        r"^<!-- API -->$",
        r"^<!-- /API -->$",
        lines,
    )


def update_options():
    option_lines = ["\n", "```lua\n"]
    config_file = os.path.join(ROOT, "lua", "quicker", "config.lua")
    option_lines = read_section(config_file, r"^\s*local default_config =", r"^}$")
    option_lines.insert(0, 'require("quicker").setup({\n')
    option_lines.insert(0, "```lua\n")
    option_lines.extend(["})\n", "```\n", "\n"])
    replace_section(
        README,
        r"^<!-- OPTIONS -->$",
        r"^<!-- /OPTIONS -->$",
        option_lines,
    )


def update_readme_toc():
    toc = ["\n"] + generate_md_toc(README, max_level=1) + ["\n"]
    replace_section(
        README,
        r"^<!-- TOC -->$",
        r"^<!-- /TOC -->$",
        toc,
    )


def gen_options_vimdoc() -> VimdocSection:
    section = VimdocSection("Options", "quicker-options", ["\n", ">lua\n"])
    config_file = os.path.join(ROOT, "lua", "quicker", "config.lua")
    option_lines = read_section(config_file, r"^\s*local default_config =", r"^}$")
    option_lines.insert(0, 'require("quicker").setup({\n')
    option_lines.extend(["})\n"])
    section.body.extend(indent(option_lines, 4))
    section.body.append("<\n")
    return section


def generate_vimdoc():
    doc = Vimdoc("quicker.txt", "quicker")
    types = parse_directory(os.path.join(ROOT, "lua"))
    funcs = types.files["quicker/init.lua"].functions
    doc.sections.extend(
        [
            gen_options_vimdoc(),
            VimdocSection(
                "API", "quicker-api", render_vimdoc_api2("quicker", funcs, types)
            ),
        ]
    )

    with open(VIMDOC, "w", encoding="utf-8") as ofile:
        ofile.writelines(doc.render())


def main() -> None:
    """Update the README"""
    update_md_api()
    update_options()
    update_readme_toc()
    generate_vimdoc()
