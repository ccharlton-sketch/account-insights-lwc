const HEADER_RE = /^(#{1,6})\s+(.*)$/;
const UL_RE = /^[-*]\s+(.*)$/;
const OL_RE = /^\d+\.\s+(.*)$/;
const HR_RE = /^-{3,}$/;
const TABLE_SEPARATOR_CELL_RE = /^:?-{3,}:?$/;

function escapeHtml(text) {
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function applyInlineFormatting(text) {
    return text.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
}

function isTableRow(line) {
    return line.length > 1 && line.startsWith('|') && line.endsWith('|');
}

function splitTableRow(line) {
    let inner = line.trim();
    if (inner.startsWith('|')) {
        inner = inner.slice(1);
    }
    if (inner.endsWith('|')) {
        inner = inner.slice(0, -1);
    }
    return inner.split('|').map((cell) => cell.trim());
}

function isTableSeparatorRow(line) {
    return splitTableRow(line).every((cell) => TABLE_SEPARATOR_CELL_RE.test(cell));
}

function buildTableHtml(rows) {
    if (!rows.length) {
        return '';
    }
    const hasHeader = rows.length > 1 && isTableSeparatorRow(rows[1]);
    const headerCells = hasHeader ? splitTableRow(rows[0]) : null;
    const bodyRows = (hasHeader ? rows.slice(2) : rows).map(splitTableRow);

    let html = '<table>';
    if (headerCells) {
        html += `<thead><tr>${headerCells
            .map((cell) => `<th>${applyInlineFormatting(cell)}</th>`)
            .join('')}</tr></thead>`;
    }
    html += `<tbody>${bodyRows
        .map((cells) => `<tr>${cells.map((cell) => `<td>${applyInlineFormatting(cell)}</td>`).join('')}</tr>`)
        .join('')}</tbody>`;
    html += '</table>';
    return html;
}

/**
 * Converts a constrained subset of Markdown (headers, bold, ordered/unordered
 * lists, paragraphs) into HTML suitable for lightning-formatted-rich-text,
 * which sanitizes output to its own allowed tag set. Input is HTML-escaped
 * before any tags are introduced.
 */
export function convertMarkdownToHtml(markdown) {
    if (!markdown) {
        return '';
    }

    const lines = markdown.replace(/\r\n/g, '\n').split('\n');
    const htmlParts = [];

    let listBuffer = [];
    let listType = null;
    let paragraphBuffer = [];
    let tableBuffer = [];

    const flushTable = () => {
        if (tableBuffer.length) {
            htmlParts.push(buildTableHtml(tableBuffer));
            tableBuffer = [];
        }
    };

    const flushList = () => {
        if (listBuffer.length) {
            const tag = listType === 'ol' ? 'ol' : 'ul';
            htmlParts.push(
                `<${tag}>${listBuffer.map((item) => `<li>${applyInlineFormatting(item)}</li>`).join('')}</${tag}>`
            );
            listBuffer = [];
            listType = null;
        }
    };

    const flushParagraph = () => {
        if (paragraphBuffer.length) {
            htmlParts.push(`<p>${applyInlineFormatting(paragraphBuffer.join(' '))}</p>`);
            paragraphBuffer = [];
        }
    };

    lines.forEach((rawLine) => {
        const line = escapeHtml(rawLine).trim();

        if (!line) {
            flushList();
            flushParagraph();
            flushTable();
            return;
        }

        if (isTableRow(line)) {
            flushList();
            flushParagraph();
            tableBuffer.push(line);
            return;
        }
        flushTable();

        if (HR_RE.test(line)) {
            flushList();
            flushParagraph();
            return;
        }

        const headerMatch = line.match(HEADER_RE);
        if (headerMatch) {
            flushList();
            flushParagraph();
            const level = headerMatch[1].length;
            const tag = `h${level}`;
            htmlParts.push(`<${tag}>${applyInlineFormatting(headerMatch[2])}</${tag}>`);
            return;
        }

        const ulMatch = line.match(UL_RE);
        if (ulMatch) {
            flushParagraph();
            if (listType && listType !== 'ul') {
                flushList();
            }
            listType = 'ul';
            listBuffer.push(ulMatch[1]);
            return;
        }

        const olMatch = line.match(OL_RE);
        if (olMatch) {
            flushParagraph();
            if (listType && listType !== 'ol') {
                flushList();
            }
            listType = 'ol';
            listBuffer.push(olMatch[1]);
            return;
        }

        flushList();
        paragraphBuffer.push(line);
    });

    flushList();
    flushParagraph();
    flushTable();

    return htmlParts.join('');
}
