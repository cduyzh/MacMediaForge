/**
 * MediaSaver 小红书博主主页全自动批量视频提取与下载助手 (控制台一键执行版)
 * 
 * 使用方式：
 *   1. 在日常 Chrome 浏览器打开博主主页 (例如: https://www.xiaohongshu.com/user/profile/659e2b41000000002201370e)
 *   2. 按 F12 (或 Cmd+Option+I) 打开控制台 (Console)
 *   3. 复制并粘贴本脚本代码，回车运行
 *   4. 脚本将自动遍历所有卡片，极速提取 1080P/720P 无水印视频直链，并自动推送到本地 ~/Downloads/XHS_Videos，同时支持浏览器一键打包下载！
 */

(async function() {
    // 移除已存在的面板
    const oldPanel = document.getElementById('lpf-helper-panel');
    if (oldPanel) oldPanel.remove();

    // 创建毛玻璃浮动控制面板
    const panel = document.createElement('div');
    panel.id = 'lpf-helper-panel';
    panel.style.cssText = `
        position: fixed;
        bottom: 24px;
        right: 24px;
        width: 380px;
        background: rgba(255, 255, 255, 0.95);
        backdrop-filter: blur(12px);
        border: 1px solid rgba(0, 0, 0, 0.1);
        border-radius: 16px;
        box-shadow: 0 12px 32px rgba(0, 0, 0, 0.18);
        padding: 18px 20px;
        z-index: 999999;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        color: #333;
        font-size: 13px;
        line-height: 1.5;
        transition: all 0.3s ease;
    `;

    panel.innerHTML = `
        <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px;">
            <div style="display: flex; align-items: center; gap: 8px;">
                <span style="font-size: 20px;">⚡️</span>
                <span style="font-weight: 700; font-size: 15px; color: #111;">小红书批量视频提取助手</span>
            </div>
            <button id="lpf-close-btn" style="background: none; border: none; font-size: 18px; cursor: pointer; color: #999;">✕</button>
        </div>
        <div id="lpf-status" style="margin-bottom: 10px; color: #555;">正在分析页面视频卡片…</div>
        <div style="background: #eee; height: 8px; border-radius: 4px; overflow: hidden; margin-bottom: 14px;">
            <div id="lpf-progress-bar" style="background: linear-gradient(90deg, #ff2442, #ff6b81); width: 0%; height: 100%; transition: width 0.3s;"></div>
        </div>
        <div id="lpf-results-preview" style="max-height: 120px; overflow-y: auto; background: #f8f9fa; border-radius: 8px; padding: 8px; font-size: 12px; margin-bottom: 14px; display: none;"></div>
        <div style="display: flex; gap: 8px; flex-wrap: wrap;">
            <button id="lpf-start-btn" style="flex: 1; padding: 8px 14px; background: #ff2442; color: #fff; border: none; border-radius: 8px; font-weight: 600; cursor: pointer;">开始自动提取全部 (30个)</button>
            <button id="lpf-browser-download-btn" style="display: none; flex: 1; padding: 8px 14px; background: #10b981; color: #fff; border: none; border-radius: 8px; font-weight: 600; cursor: pointer;">浏览器直接下载全部</button>
            <button id="lpf-copy-btn" style="display: none; padding: 8px 14px; background: #4f46e5; color: #fff; border: none; border-radius: 8px; font-weight: 600; cursor: pointer;">复制直链列表</button>
        </div>
    `;

    document.body.appendChild(panel);

    document.getElementById('lpf-close-btn').onclick = () => panel.remove();

    const statusEl = document.getElementById('lpf-status');
    const progressBar = document.getElementById('lpf-progress-bar');
    const previewEl = document.getElementById('lpf-results-preview');
    const startBtn = document.getElementById('lpf-start-btn');
    const downloadBtn = document.getElementById('lpf-browser-download-btn');
    const copyBtn = document.getElementById('lpf-copy-btn');

    // 查找页面卡片
    function getCards() {
        let cards = Array.from(document.querySelectorAll('section.note-item, .note-item, section'));
        return cards.filter(c => c.querySelector('img') || c.innerText.trim().length > 0);
    }

    let cards = getCards();
    statusEl.innerText = `已就绪！检测到当前页面有 ${cards.length} 个视频卡片。点击下方按钮开始全自动提取。`;

    const extractedVideos = [];

    // 关闭弹窗
    function closeCurrentModal() {
        document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, which: 27, bubbles: true }));
        const closeBtn = document.querySelector('.close-circle, .close, [aria-label="关闭"], .close-box, svg.close');
        if (closeBtn) {
            try { closeBtn.click(); } catch(e) {}
        }
    }

    // 自动抓取主流程
    startBtn.onclick = async () => {
        startBtn.disabled = true;
        startBtn.style.opacity = '0.5';
        previewEl.style.display = 'block';

        cards = getCards();
        const total = cards.length;
        if (total === 0) {
            statusEl.innerText = '未在页面上找到卡片，请刷新后重试！';
            return;
        }

        statusEl.innerText = `正在处理第 1 / ${total} 个作品…`;

        for (let i = 0; i < total; i++) {
            const card = cards[i];
            const titleEl = card.querySelector('.title, .footer, span, [class*="title"]');
            const cardTitle = (titleEl ? titleEl.innerText.trim() : `作品_${i + 1}`) || `视频_${i + 1}`;

            // 滚动到该卡片并点击
            card.scrollIntoView({ behavior: 'smooth', block: 'center' });
            await new Promise(r => setTimeout(r, 200));

            card.click();
            await new Promise(r => setTimeout(r, 600));

            // 从弹窗或状态机提取视频直链
            let videoUrl = '';
            let finalTitle = cardTitle;

            // 方式 1: 直接读取 DOM 中的 video 标签
            const videoEl = document.querySelector('video');
            if (videoEl && (videoEl.currentSrc || videoEl.src)) {
                videoUrl = videoEl.currentSrc || videoEl.src;
            }

            // 方式 2: 从 window.__INITIAL_STATE__ 读取高清 masterUrl
            try {
                const state = window.__INITIAL_STATE__;
                const noteDetailMap = state?.note?.noteDetailMap || {};
                const currentNote = Object.values(noteDetailMap).pop()?.note;
                if (currentNote) {
                    if (currentNote.title || currentNote.desc) {
                        finalTitle = currentNote.title || currentNote.desc;
                    }
                    const streams = currentNote.video?.media?.stream;
                    if (streams) {
                        const h264List = streams.h264 || [];
                        const h265List = streams.h265 || [];
                        if (h264List.length > 0) {
                            videoUrl = h264List[0].masterUrl || h264List[0].backupUrls?.[0] || videoUrl;
                        } else if (h265List.length > 0) {
                            videoUrl = h265List[0].masterUrl || h265List[0].backupUrls?.[0] || videoUrl;
                        }
                    }
                    if (!videoUrl && currentNote.video?.consumer?.originVideoKey) {
                        videoUrl = `https://sns-video-bd.xhscdn.com/${currentNote.video.consumer.originVideoKey}`;
                    }
                }
            } catch(e) {}

            if (videoUrl) {
                // 清洗标题
                finalTitle = finalTitle.replace(/[\\/:*?"<>|\n\r]/g, ' ').trim().slice(0, 45);
                const item = {
                    index: i + 1,
                    title: `${String(i + 1).padStart(2, '0')}_${finalTitle}`,
                    url: videoUrl
                };
                extractedVideos.push(item);

                // 尝试推送到本地接收器 (如果运行着 MediaSaver 本地服务)
                try {
                    fetch('http://127.0.0.1:8765/api/push_video', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify(item)
                    }).catch(() => {});
                } catch(e) {}

                previewEl.innerHTML += `<div style="padding: 2px 0; color: #10b981;">✅ [${i + 1}/${total}] ${item.title}</div>`;
                previewEl.scrollTop = previewEl.scrollHeight;
            } else {
                previewEl.innerHTML += `<div style="padding: 2px 0; color: #f59e0b;">⚠️ [${i + 1}/${total}] 未检测到视频流 (可能为图文)</div>`;
            }

            // 关闭弹窗
            closeCurrentModal();
            await new Promise(r => setTimeout(r, 250));

            // 更新进度条
            const pct = Math.round(((i + 1) / total) * 100);
            progressBar.style.width = `${pct}%`;
            statusEl.innerText = `处理进度: ${i + 1} / ${total} (${pct}%)`;
        }

        statusEl.innerHTML = `🎉 <b>处理完成！共成功提取 ${extractedVideos.length} 个视频直链！</b>`;
        startBtn.style.display = 'none';
        downloadBtn.style.display = 'block';
        copyBtn.style.display = 'block';

        // 浏览器直接下载
        downloadBtn.onclick = async () => {
            downloadBtn.disabled = true;
            statusEl.innerText = '正在启动浏览器多任务下载…';
            for (let v of extractedVideos) {
                const a = document.createElement('a');
                a.href = v.url;
                a.download = `${v.title}.mp4`;
                a.target = '_blank';
                document.body.appendChild(a);
                a.click();
                a.remove();
                await new Promise(r => setTimeout(r, 400));
            }
            statusEl.innerText = '✅ 全部视频下载指令已触发！请查看浏览器下载列表。';
        };

        // 复制链接列表
        copyBtn.onclick = () => {
            const text = extractedVideos.map(v => `${v.title}: ${v.url}`).join('\n');
            navigator.clipboard.writeText(text);
            copyBtn.innerText = '已复制！';
            setTimeout(() => { copyBtn.innerText = '复制直链列表'; }, 2000);
        };
    };
})();
