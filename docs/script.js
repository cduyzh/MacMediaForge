(() => {
    const status = document.getElementById('copy-status');
    const resetTimers = new WeakMap();

    function selectCommand(code) {
        const selection = window.getSelection();
        if (!selection) return;
        const range = document.createRange();
        range.selectNodeContents(code);
        selection.removeAllRanges();
        selection.addRange(range);
    }

    document.querySelectorAll('[data-copy]').forEach(button => {
        button.addEventListener('click', async () => {
            const code = document.getElementById(button.dataset.copy);
            if (!code || !code.textContent.trim()) {
                if (status) status.textContent = '未找到命令，请刷新页面后重试。';
                return;
            }

            const originalLabel = '复制命令';
            window.clearTimeout(resetTimers.get(button));
            button.disabled = true;
            button.textContent = '正在复制…';
            button.setAttribute('aria-busy', 'true');

            try {
                if (!navigator.clipboard || !window.isSecureContext) {
                    throw new Error('Clipboard unavailable');
                }
                await navigator.clipboard.writeText(code.textContent.trim());
                button.textContent = '已复制';
                if (status) status.textContent = '命令已复制。请先确认文件路径，再粘贴到终端运行。';
            } catch {
                selectCommand(code);
                button.textContent = '手动复制';
                if (status) status.textContent = '未能自动复制，命令已选中。请使用系统复制快捷键，或手动选择命令复制。';
            } finally {
                button.disabled = false;
                button.removeAttribute('aria-busy');
                resetTimers.set(button, window.setTimeout(() => {
                    button.textContent = originalLabel;
                    resetTimers.delete(button);
                }, 2500));
            }
        });
    });
})();
