import {useState, useEffect, useCallback, useRef} from "react";
import {useSearchParams, useNavigate} from "react-router";
import {ArrowLeft, Loader2, AlertCircle, Download} from "lucide-react";
import Artplayer from "artplayer";
import Hls from "hls.js";
import artplayerPluginHlsControl from "artplayer-plugin-hls-control";
import {useThemeStore} from "@/stores/theme";
import {THEMES} from "@/app/components/Navbar";
import {GradientText} from "@/app/components/GradientText";
import {ArtVideoPlayer, type ArtVideoPlayerHandle} from "@/app/components/ArtVideoPlayer";
import {PlayEpisodeList} from "@/app/components/PlayEpisodeList";
import {PlayInfoPanel} from "@/app/components/PlayInfoPanel";
import {EpisodeNav} from "@/app/components/EpisodeNav";
import {ResourceSwitcher} from "@/app/components/ResourceSwitcher";
import {PlayHistoryPanel} from "@/app/components/PlayHistoryPanel";
import {DownloadEpisodeDialog} from "@/app/components/DownloadEpisodeDialog";
import {getResourceDetail, parsePlaySources, getCachedGroupData} from "@/api/search";
import {checkDownload, getDownloadFileUrl} from "@/api/download";
import {getPlayHistory} from "@/api/user-data";
import {usePlayHistory} from "@/hooks/usePlayHistory";
import {usePlayProgress} from "@/hooks/usePlayProgress";
import {useAutoPlayNext} from "@/hooks/useAutoPlayNext";
import {useM3u8Check} from "@/hooks/useM3u8Check";
import {usePlayHistoryStore} from "@/stores/play-history";
import {getStreamConfig, buildProxyM3u8UrlWithToken, extractSessionFromM3u8, isM3u8Url} from "@/api/stream";
import {invalidateTempTokenCache} from "@/api/tempToken";
import type {SearchResultItem, ResourceDetailResp, PlaySource, StreamConfig} from "@/types/api";
import "@/styles/artplayer-theme.css";

/** 根据 URL 和本地文件信息推断 Artplayer 的 type 字段，确保 customType 回调能正确触发 */
function inferArtplayerType(url: string, isLocalFile: boolean, localFileFormat: string): string | undefined {
    if (isLocalFile && localFileFormat === 'mp4') return 'mp4';
    if (/\.m3u8(\?.*)?$/i.test(url) || url.includes('.m3u8')) return 'm3u8';
    return undefined;
}

function isDirectPlayUrl(url: string): boolean {
    if (!url) return false;
    const directPatterns = /\.(m3u8|mp4|mkv|flv|ts|f4v|mpd)(\?.*)?$/i;
    if (directPatterns.test(url)) return true;
    if (url.includes('.m3u8') && !url.includes('.html')) return true;
    if (/^\d+$/.test(url)) return false;
    const iframePatterns = /\/share\/|\/player\.php|\/iframe|embed|\.html/i;
    if (iframePatterns.test(url)) return false;
    return true;
}

export default function PlayPage() {
    const [searchParams, setSearchParams] = useSearchParams();
    const navigate = useNavigate();
    const activeTheme = useThemeStore((s) => s.activeTheme);
    const theme = THEMES[activeTheme];
    const groupKey = searchParams.get("group_key") || "";
    const name = searchParams.get("name") || "";
    const site = searchParams.get("site") || "";
    const vodIdParam = parseInt(searchParams.get("vod_id") || "0", 10);
    const epParam = parseInt(searchParams.get("ep") || "0", 10);
    const sourceParam = parseInt(searchParams.get("source") || "0", 10);

    const [groupItems, setGroupItems] = useState<SearchResultItem[]>([]);
    const [activeDomain, setActiveDomain] = useState(site);
    const [detail, setDetail] = useState<ResourceDetailResp | null>(null);
    const [sources, setSources] = useState<PlaySource[]>([]);
    const [activeSourceIndex, setActiveSourceIndex] = useState(sourceParam);
    const [activeEpIndex, setActiveEpIndex] = useState(epParam);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState("");
    const [downloadOpen, setDownloadOpen] = useState(false);
    const [localFileUrl, setLocalFileUrl] = useState<string | null>(null);
    const [localFileFormat, setLocalFileFormat] = useState<string>('mp4');
    const [checkingLocal, setCheckingLocal] = useState(false);
    const checkDownloadSeqRef = useRef(0);

    // ====== 流代理相关状态 ======
    const [streamConfig, setStreamConfig] = useState<StreamConfig | null>(null);
    const [streamSessionKey, setStreamSessionKey] = useState<string | null>(null);
    const [currentSegmentIndex, setCurrentSegmentIndex] = useState(0);
    const [bufferedAheadCount, setBufferedAheadCount] = useState(0);
    // 代理 URL（异步获取 tempToken 后拼接）
    const [proxyUrl, setProxyUrl] = useState<string | null>(null);

    // ====== m3u8 链接检测 ======
    const m3u8Check = useM3u8Check();

    // ====== 播放器生命周期管理（由 PlayPage 主动控制） ======
    const artRef = useRef<Artplayer | null>(null);
    const playerHandleRef = useRef<ArtVideoPlayerHandle>(null);
    // 创建序列号：防止过期的 effect 创建播放器
    const createSeqRef = useRef(0);
    // 续播 seek 时间：由 getPlayHistory effect 写入，播放器 loadedmetadata 事件读取并 seek
    const pendingSeekTimeRef = useRef<number | null>(null);

    // ====== 用 ref 存储进度相关最新值，使 destroyArtInstance 引用稳定 ======
    // 先声明 ref（初始值为 undefined/null），在变量声明后再赋值 .current
    const progressRef = useRef<ReturnType<typeof usePlayProgress> | null>(null);
    const currentVodIdRef = useRef(0);
    const activeDomainRef = useRef('');
    const activeSourceIndexRef = useRef(0);
    const activeEpIndexRef = useRef(0);
    const episodeNameRef = useRef('');
    const isUsingProxyRef = useRef<boolean>(false);
    const streamSessionKeyRef = useRef<string | null>(null);
    const currentSegmentIndexRef = useRef(0);
    const bufferedAheadCountRef = useRef(0);

    const currentSource = sources[activeSourceIndex];
    const currentEpisode = currentSource?.episodes[activeEpIndex];
    const remoteUrl = currentEpisode?.url || "";
    const episodeName = currentEpisode?.name || "";
    // 本地文件优先；检查中时暂不使用远程 URL，避免先播放远程再切换本地的闪烁
    const rawPlayUrl = localFileUrl || (checkingLocal ? "" : remoteUrl);
    // 流代理：如果是 m3u8 且代理开启，则使用代理 URL（需异步获取 tempToken）
    const useProxy = streamConfig?.enabled && isM3u8Url(remoteUrl) && !localFileUrl;
    const playUrl = useProxy ? (proxyUrl || "") : rawPlayUrl;
    const isLocalFile = !!localFileUrl;
    const isUsingProxy = useProxy;
    const maxEpIdx = Math.max((currentSource?.episodes.length || 1) - 1, 0);
    const isLastEpisode = activeEpIndex >= maxEpIdx;
    const currentVodId = groupItems.find((i) => i.resource_domain === activeDomain)?.vod_id || vodIdParam || 0;

    // 提供完整 VOD 元信息（退出上送时填充，避免空字符串覆盖后端数据）
    const getMeta = useCallback(() => ({
        vodName: detail?.vod_name ?? '',
        vodPic: detail?.vod_pic ?? '',
        resourceName: detail?.resource_name ?? '',
        groupKey,
    }), [detail?.vod_name, detail?.vod_pic, detail?.resource_name, groupKey]);

    // 播放进度记忆
    const progress = usePlayProgress({
        vodId: currentVodId, sourceIndex: activeSourceIndex, epIndex: activeEpIndex,
        resourceDomain: activeDomain, epName: episodeName,
        streamData: isUsingProxy && streamSessionKey ? {
            session: streamSessionKey,
            current_index: currentSegmentIndex,
            buffered_ahead: bufferedAheadCount,
        } : undefined,
        getMeta,
    });

    // 变量声明完成后，同步最新值到 ref
    progressRef.current = progress;
    currentVodIdRef.current = currentVodId;
    activeDomainRef.current = activeDomain;
    activeSourceIndexRef.current = activeSourceIndex;
    activeEpIndexRef.current = activeEpIndex;
    episodeNameRef.current = episodeName;
    isUsingProxyRef.current = !!isUsingProxy;
    streamSessionKeyRef.current = streamSessionKey;
    currentSegmentIndexRef.current = currentSegmentIndex;
    bufferedAheadCountRef.current = bufferedAheadCount;

    // 播放历史 hook
    const {recordPlay} = usePlayHistory();

    const handleEpisodeSelect = useCallback((idx: number) => {
        setActiveEpIndex(idx);
        const p = new URLSearchParams(searchParams);
        p.set("ep", String(idx));
        setSearchParams(p, {replace: true});
        if (detail) {
            const epName = sources[activeSourceIndex]?.episodes[idx]?.name || "";
            recordPlay({
                vodId: detail.vod_id, vodName: detail.vod_name, vodPic: detail.vod_pic,
                resourceDomain: detail.resource_domain, resourceName: detail.resource_name,
                groupKey, sourceIndex: activeSourceIndex, epIndex: idx, epName,
                progress: 0, currentTime: 0, duration: 0, updatedAt: Date.now(),
            });
        }
    }, [searchParams, detail, sources, activeSourceIndex, groupKey, recordPlay, setSearchParams]);

    // 连播逻辑
    const autoPlayNext = useAutoPlayNext({
        isLastEpisode, enabled: true,
        onNext: () => {
            if (activeEpIndex < maxEpIdx) handleEpisodeSelect(activeEpIndex + 1);
        },
        getCurrentTime: () => artRef.current?.video?.currentTime ?? 0,
        getDuration: () => artRef.current?.video?.duration ?? 0,
    });

    // ====== 销毁 Artplayer 实例的辅助函数（引用稳定，通过 ref 读取最新值） ======
    const destroyArtInstance = useCallback(() => {
        if (!artRef.current) return;
        const art = artRef.current;
        try {
            if (art.video) {
                art.video.pause();
                // 通过 ref 读取最新值保存进度，避免依赖 progress 引用导致 useCallback 不稳定
                const p = progressRef.current;
                if (p) p.saveProgress(art.video);
                // 彻底清空视频源，防止后台继续播放音频
                art.video.removeAttribute('src');
                art.video.load();
            }
        } catch { /* ignore */
        }
        if (art.hls) {
            try {
                (art.hls as { destroy: () => void }).destroy();
            } catch { /* ignore */
            }
            art.hls = null;
        }
        try {
            art.destroy(true);
        } catch { /* ignore */
        }
        artRef.current = null;
    }, []); // 空依赖：通过 ref 读取最新值，引用永远稳定

    // ====== 核心：监听 playUrl 变化，主动控制播放器创建/销毁 ======
    useEffect(() => {
        const seq = ++createSeqRef.current;

        if (!playUrl) {
            destroyArtInstance();
            return;
        }
        const directPlay = isLocalFile || isDirectPlayUrl(playUrl);
        if (!directPlay) {
            destroyArtInstance();
            return;
        }
        // 销毁旧实例
        destroyArtInstance();
        autoPlayNext.resetCountdown();

        // 延迟创建新实例，确保旧实例销毁和 DOM 清理完成
        const createTimer = setTimeout(() => {
            // 序列号检查：如果有更新的 effect 已触发，跳过本次创建
            if (seq !== createSeqRef.current) return;
            // 二次检查：确保容器仍然存在且未被卸载
            const el = playerHandleRef.current?.containerRef.current;
            if (!el) return;

            const inferredType = inferArtplayerType(playUrl, isLocalFile, localFileFormat);
            const art = new Artplayer({
                container: el,
                url: playUrl,
                ...(inferredType ? {type: inferredType} : {}),
                volume: 0.8, autoplay: true, autoSize: false, loop: false,
                playbackRate: true, setting: true, hotkey: true, pip: true, mutex: true,
                fullscreen: true, fullscreenWeb: true, miniProgressBar: true, playsInline: true,
                theme: theme.from,
                cssVar: {
                    '--art-theme': theme.from, '--art-progress-color': theme.from,
                    '--art-hover-color': theme.from, '--art-border-radius': '0.75rem',
                    '--art-bottom-height': '46px', '--art-control-height': '46px',
                },
                customType: {
                    m3u8: (video: HTMLVideoElement, url: string, art: Artplayer) => {
                        if (Hls.isSupported()) {
                            const hls = new Hls({
                                maxBufferLength: 30,
                                maxMaxBufferLength: 60,
                                // tempToken 已通过 URL query 参数传递，后端 TempTokenAuth 中间件
                                // 从 URL 读取 token，无需再设置 Authorization header
                            });
                            // 提取 session key（从第一个分片的 URL 中提取）
                            // 使用 Hls.Events.FRAG_LOADED 获取分片加载事件
                            // eslint-disable-next-line @typescript-eslint/no-explicit-any
                            hls.on(Hls.Events.FRAG_LOADED, (_event: any, data: any) => {
                                const fragUrl = data?.frag?.url;
                                if (fragUrl) {
                                    // 从分片 URL 中提取 session（格式：/api/stream/proxy/ts?session=<key>&index=<N>）
                                    const session = extractSessionFromM3u8(fragUrl);
                                    if (session) {
                                        setStreamSessionKey(session);
                                    }
                                    // 追踪当前分片索引
                                    const relindex = data?.frag?.relindex;
                                    if (typeof relindex === 'number') {
                                        setCurrentSegmentIndex(relindex);
                                    }
                                }
                            });
                            // 处理分片加载错误
                            // - 401: tempToken 过期，需要重新获取 token 并重建代理 URL
                            // - 410: 临时文件已清理，需要重新触发播放流程
                            // eslint-disable-next-line @typescript-eslint/no-explicit-any
                            hls.on(Hls.Events.ERROR, async (_event: any, data: any) => {
                                const resp = data?.response;
                                if (resp && resp.status === 401 && isUsingProxy) {
                                    console.warn('[PlayPage] tempToken expired (401), refreshing proxy URL');
                                    // 清除 tempToken 缓存，确保下次获取新 token
                                    invalidateTempTokenCache();
                                    // 清除 proxyUrl，触发 useEffect 重新获取 tempToken 并重建 URL
                                    setProxyUrl(null);
                                    return;
                                }
                                if (resp && resp.status === 410) {
                                    console.warn('[PlayPage] Segment expired (410 Gone), clearing session and reloading');
                                    setStreamSessionKey(null);
                                    // 清除本地文件缓存，强制重新评估播放源
                                    setLocalFileUrl(null);
                                    // 重新加载 source 以触发播放流程重试
                                    setTimeout(() => {
                                        if (art.hls) {
                                            (art.hls as { destroy: () => void }).destroy();
                                            art.hls = null;
                                        }
                                        video.pause();
                                        video.removeAttribute('src');
                                        video.load();
                                    }, 100);
                                    return;
                                }

                                // 处理致命错误：检测链接是否可用
                                // eslint-disable-next-line @typescript-eslint/no-explicit-any
                                if (data?.fatal) {
                                    console.warn('[PlayPage] HLS fatal error, checking m3u8 URL:', data);
                                    art.notice.show = '正在检测链接...';

                                    // 检测原始 m3u8 URL（如果使用代理，使用 remoteUrl；否则使用当前 url）
                                    const targetUrl = isUsingProxy ? remoteUrl : url;
                                    if (!targetUrl) return;

                                    try {
                                        const result = await m3u8Check.checkSingle(targetUrl);
                                        if (!result.available) {
                                            art.notice.show = '链接不可用，请切换线路';
                                        } else if (isUsingProxy) {
                                            art.notice.show = '代理缓存异常，正在重试...';
                                            // 代理模式下可用，清除 session 强制重试
                                            setStreamSessionKey(null);
                                            setLocalFileUrl(null);
                                            setTimeout(() => {
                                                if (art.hls) {
                                                    (art.hls as { destroy: () => void }).destroy();
                                                    art.hls = null;
                                                }
                                                video.pause();
                                                video.removeAttribute('src');
                                                video.load();
                                            }, 100);
                                        } else {
                                            art.notice.show = '播放出错，请重试';
                                        }
                                    } catch (err) {
                                        console.error('[PlayPage] URL check failed:', err);
                                        art.notice.show = '播放出错，请重试';
                                    }
                                }
                            });
                            hls.loadSource(url);
                            hls.attachMedia(video);
                            art.hls = hls;
                            art.on('destroy', () => {
                                hls.destroy();
                                art.hls = null;
                            });
                        } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
                            video.src = url;
                        } else {
                            art.notice.show = '不支持 HLS 播放';
                        }
                    },
                },
                plugins: inferredType === 'm3u8' ? [artplayerPluginHlsControl({
                    quality: {
                        auto: '自动', title: '画质',
                        getName: (level: object) => (level as Record<string, unknown>).name as string || `${(level as Record<string, unknown>).height}P`
                    },
                })] : [],
            });
            artRef.current = art;

            art.on('video:loadedmetadata', () => {
                if (art.video) {
                    // 续播：优先从 pendingSeekTimeRef 读取（由 getPlayHistory effect 写入）
                    const seekTime = pendingSeekTimeRef.current;
                    if (seekTime !== null && seekTime > 0 && art.video.duration > 0 && seekTime < art.video.duration) {
                        console.log('[PlayPage] loadedmetadata: seek to', seekTime);
                        art.video.currentTime = seekTime;
                        pendingSeekTimeRef.current = null; // seek 后清除，避免重复
                    } else {
                        // fallback: 通过 usePlayProgress 的 onLoadedMetadata 恢复
                        progressRef.current?.onLoadedMetadata(art.video);
                    }
                }
            });
            art.on('video:timeupdate', () => {
                if (art.video) {
                    progressRef.current?.onTimeUpdate(art.video);
                    autoPlayNext.checkAutoPlay();
                }
            });
            art.on('hover', (state: boolean) => {
                if (!state && art.setting.show) art.setting.show = false;
            });
            art.on('destroy', () => {
                if (art.video) progressRef.current?.saveProgress(art.video);
                artRef.current = null;
            });
        }, 60);

        return () => {
            clearTimeout(createTimer);
            // 【关键修复】销毁已创建的 Artplayer 实例，防止后台残留播放
            destroyArtInstance();
        };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [playUrl, isLocalFile, localFileFormat, theme.from]);
    // 注意：destroyArtInstance 已移出依赖列表（引用稳定，空依赖），避免不必要的 effect 重触发

    // 页面卸载时销毁播放器 + 兜底清理所有 video/iframe
    useEffect(() => {
        const cleanup = () => {
            destroyArtInstance();
            // 兜底：清理所有残留的 video 和 iframe 元素
            document.querySelectorAll('video').forEach(v => {
                v.pause();
                v.removeAttribute('src');
                v.load();
            });
            document.querySelectorAll('iframe').forEach(iframe => {
                iframe.src = 'about:blank';
            });
        };
        window.addEventListener('beforeunload', cleanup);
        return () => {
            cleanup();
            window.removeEventListener('beforeunload', cleanup);
        };
    }, [destroyArtInstance]);

    useEffect(() => {
        if (!groupKey) return;
        const cached = getCachedGroupData(groupKey);
        if (cached) setGroupItems(cached);
    }, [groupKey]);

    // 加载流代理配置
    useEffect(() => {
        getStreamConfig().then((config) => {
            setStreamConfig(config);
        }).catch(() => {
            // 配置获取失败时不启用代理
            setStreamConfig(null);
        });
    }, []);

    // 异步获取带 tempToken 的代理 URL
    // 当 useProxy 或 remoteUrl 变化时，重新获取 tempToken 并构建代理 URL
    useEffect(() => {
        if (!useProxy || !remoteUrl) {
            setProxyUrl(null);
            return;
        }
        let cancelled = false;
        buildProxyM3u8UrlWithToken(remoteUrl).then((url) => {
            if (!cancelled) setProxyUrl(url);
        }).catch((err) => {
            console.error('[PlayPage] Failed to build proxy URL with tempToken:', err);
            if (!cancelled) setProxyUrl(null);
        });
        return () => { cancelled = true; };
    }, [useProxy, remoteUrl]);

    const fetchDetail = useCallback(async (domain: string, vodId: number | undefined) => {
        if (!domain || !vodId) {
            setError("缺少资源站点或视频ID");
            return;
        }
        setLoading(true);
        setError("");
        try {
            const resp = await getResourceDetail({site: domain, vod_id: vodId});
            setDetail(resp);
            const parsed = parsePlaySources(resp.vod_play_url || "", resp.vod_play_from);
            setSources(parsed);
            setActiveSourceIndex((p) => (p >= parsed.length ? 0 : p));
            if (parsed.length > 0) setActiveEpIndex((p) => (p >= parsed[0].episodes.length ? 0 : p));
        } catch (e: unknown) {
            setError(e instanceof Error ? e.message : "获取详情失败");
            setDetail(null);
            setSources([]);
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        const target = groupItems.find((i) => i.resource_domain === site);
        if (target?.vod_id) {
            fetchDetail(target.resource_domain, target.vod_id);
        } else if (groupItems.length > 0 && site) {
            const first = groupItems[0];
            if (first?.vod_id) {
                setActiveDomain(first.resource_domain);
                fetchDetail(first.resource_domain, first.vod_id);
            }
        }
    }, [groupItems, site, fetchDetail]);

    useEffect(() => {
        if (!groupKey && vodIdParam > 0 && site) {
            fetchDetail(site, vodIdParam);
        }
    }, [groupKey, vodIdParam, site, fetchDetail]);

    // 检查本地下载文件
    useEffect(() => {
        if (!detail) {
            setLocalFileUrl(null);
            setLocalFileFormat('mp4');
            setCheckingLocal(false);
            return;
        }
        const resourceDomain = detail.resource_domain;
        if (!resourceDomain) {
            setLocalFileUrl(null);
            setLocalFileFormat('mp4');
            setCheckingLocal(false);
            return;
        }
        const seq = ++checkDownloadSeqRef.current;
        // 立即标记为检查中，并清空本地文件 URL
        // 这样 playUrl 会立即变为空，防止在检查期间使用远程 URL 创建播放器
        setCheckingLocal(true);
        setLocalFileUrl(null);
        checkDownload({
            resource_domain: resourceDomain, vod_id: detail.vod_id,
            source_index: activeSourceIndex, ep_index: activeEpIndex,
        }).then((resp) => {
            if (seq !== checkDownloadSeqRef.current) return;
            if (resp.found && resp.task_id > 0 && resp.file_format === 'mp4') {
                console.log('[PlayPage] 本地 MP4 文件已找到, task_id:', resp.task_id);
                setLocalFileUrl(getDownloadFileUrl(resp.task_id));
                setLocalFileFormat('mp4');
            } else if (resp.found && resp.file_format === 'ts') {
                console.log('[PlayPage] 本地文件为 TS 格式，回退远程流, task_id:', resp.task_id);
                setLocalFileUrl(null);
                setLocalFileFormat('ts');
            } else {
                console.log('[PlayPage] 未找到本地下载文件, vod_id:', detail.vod_id, 'domain:', resourceDomain);
                setLocalFileUrl(null);
                setLocalFileFormat('mp4');
            }
        }).catch((err) => {
            if (seq !== checkDownloadSeqRef.current) return;
            console.error('[PlayPage] checkDownload 失败:', err);
            setLocalFileUrl(null);
            setLocalFileFormat('mp4');
        }).finally(() => {
            if (seq !== checkDownloadSeqRef.current) return;
            setCheckingLocal(false);
        });
    }, [detail, activeSourceIndex, activeEpIndex]);

    // ====== 播放前获取最新进度用于续播 ======
    // 监听 vodId+domain+epIndex 变化，调用 get 接口获取后端最新进度，
    // 将 seek 时间写入 pendingSeekTimeRef（供 loadedmetadata 事件读取 seek），
    // 并兜底：若 video 已 ready 则直接 seek（处理 loadedmetadata 先于 get 返回的时序）
    const restoreSeqRef = useRef(0);
    useEffect(() => {
        // 切换剧集/源时清除旧的 seek 时间
        pendingSeekTimeRef.current = null;
        // 优先使用 currentVodId（来自 groupItems），fallback 到 URL 参数 vodIdParam
        const effectiveVodId = currentVodId || vodIdParam;
        console.log('[PlayPage] restore effect', { currentVodId, vodIdParam, effectiveVodId, activeDomain, activeEpIndex });
        if (!effectiveVodId || !activeDomain) return;
        const seq = ++restoreSeqRef.current;
        getPlayHistory({
            vod_id: effectiveVodId,
            resource_domain: activeDomain,
            ep_index: activeEpIndex,
        }).then((item) => {
            // 过期请求忽略（切集/切源后旧请求返回）
            if (seq !== restoreSeqRef.current) {
                console.log('[PlayPage] restore seq mismatch, skipping', { seq, current: restoreSeqRef.current });
                return;
            }
            console.log('[PlayPage] getPlayHistory result', item ? { vod_id: item.vod_id, currentTime: item.current_time, progress: item.progress } : null);
            if (!item) return; // 无记录，从头播放
            // 进度 > 95% 视为已看完，不恢复
            if (item.progress > 95) return;
            // 将 seek 时间写入 ref，供 loadedmetadata 事件读取
            if (item.current_time > 0) {
                pendingSeekTimeRef.current = item.current_time;
            }
            // 同时更新 store（供 usePlayProgress 的 onLoadedMetadata fallback 使用）
            usePlayHistoryStore.getState().hydrateRecord({
                vodId: item.vod_id, vodName: item.vod_name, vodPic: item.vod_pic,
                resourceDomain: item.resource_domain, resourceName: item.resource_name,
                groupKey: item.group_key, sourceIndex: item.source_index,
                epIndex: item.ep_index, epName: item.ep_name,
                progress: item.progress, currentTime: item.current_time,
                duration: item.duration, updatedAt: item.updated_at,
            });
            // 兜底：若播放器 video 已 ready（loadedmetadata 已触发），直接 seek
            // 如果 video 还没 ready，pendingSeekTimeRef 会在 loadedmetadata 事件中被读取
            const trySeek = () => {
                const video = artRef.current?.video;
                console.log('[PlayPage] trySeek check', { hasVideo: !!video, duration: video?.duration, seekTime: item.current_time });
                if (video && video.duration > 0 && item.current_time < video.duration) {
                    console.log('[PlayPage] trySeek: seek to', item.current_time);
                    video.currentTime = item.current_time;
                    pendingSeekTimeRef.current = null; // 已经 seek，清除避免重复
                    return true;
                }
                return false;
            };
            // 立即尝试 seek
            if (!trySeek()) {
                // video 还没 ready，轮询等待（最多 5 秒，每 200ms 检查一次）
                let attempts = 0;
                const pollTimer = setInterval(() => {
                    attempts++;
                    if (trySeek() || attempts >= 25) {
                        clearInterval(pollTimer);
                        if (attempts >= 25) {
                            console.warn('[PlayPage] trySeek: timed out waiting for video ready');
                        }
                    }
                }, 200);
            }
        }).catch((err) => { console.error('[PlayPage] getPlayHistory error', err); });
    }, [currentVodId, vodIdParam, activeDomain, activeEpIndex]);

    // 记录播放历史
    useEffect(() => {
        if (!detail || !currentSource || !currentEpisode) return;
        recordPlay({
            vodId: detail.vod_id, vodName: detail.vod_name, vodPic: detail.vod_pic,
            resourceDomain: detail.resource_domain, resourceName: detail.resource_name,
            groupKey, sourceIndex: activeSourceIndex, epIndex: activeEpIndex, epName: episodeName,
            progress: 0, currentTime: 0, duration: 0, updatedAt: Date.now(),
        });
    }, [detail?.vod_id, detail?.resource_domain, activeSourceIndex, activeEpIndex]);

    // 当播放源变化时，批量检测所有剧集链接
    useEffect(() => {
        if (!currentSource || currentSource.episodes.length === 0) return;
        const urls = currentSource.episodes
            .map(ep => ep.url)
            .filter(url => url && (url.includes('.m3u8') || url.includes('.mp4')));
        if (urls.length > 0) {
            m3u8Check.checkUrls(urls);
        }
    }, [currentSource]);

    const handleResourceChange = (item: SearchResultItem) => {
        if (item.resource_domain === activeDomain) return;
        setActiveDomain(item.resource_domain);
        setActiveEpIndex(0);
        setActiveSourceIndex(0);
        fetchDetail(item.resource_domain, item.vod_id);
    };

    const handleSourceSelect = (idx: number) => {
        if (idx === activeSourceIndex) return;
        setActiveSourceIndex(idx);
        setActiveEpIndex(0);
        const p = new URLSearchParams(searchParams);
        p.set("source", String(idx));
        p.set("ep", "0");
        setSearchParams(p, {replace: true});
        if (detail) {
            const epName = sources[idx]?.episodes[0]?.name || "";
            recordPlay({
                vodId: detail.vod_id, vodName: detail.vod_name, vodPic: detail.vod_pic,
                resourceDomain: detail.resource_domain, resourceName: detail.resource_name,
                groupKey, sourceIndex: idx, epIndex: 0, epName,
                progress: 0, currentTime: 0, duration: 0, updatedAt: Date.now(),
            });
        }
    };

    const handlePrev = () => {
        if (activeEpIndex > 0) handleEpisodeSelect(activeEpIndex - 1);
    };
    const handleNext = () => {
        if (activeEpIndex < maxEpIdx) handleEpisodeSelect(activeEpIndex + 1);
    };

    return (
        <div className="px-4 md:px-8 lg:px-12 py-4">
            {/* 顶部导航 */}
            <div className="flex items-center gap-3 mb-4">
                <button
                    onClick={() => navigate(-1)}
                    className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg transition-all duration-200"
                    style={{background: "var(--bg-elevated)", color: "var(--text-muted)"}}
                    onMouseEnter={(e) => {
                        e.currentTarget.style.background = theme.subtle;
                        e.currentTarget.style.color = theme.from;
                    }}
                    onMouseLeave={(e) => {
                        e.currentTarget.style.background = "var(--bg-elevated)";
                        e.currentTarget.style.color = "var(--text-muted)";
                    }}
                >
                    <ArrowLeft size={14}/>
                    <span className="text-xs" style={{fontFamily: "var(--font-display)"}}>返回</span>
                </button>
                <h1 style={{fontFamily: "var(--font-display)", fontWeight: 800, fontSize: "1.1rem"}}>
                    <GradientText from={theme.from} to={theme.to}>{name || "播放"}</GradientText>
                </h1>
                {/* 下载按钮 */}
                {detail && sources.length > 0 && (
                    <button
                        onClick={() => setDownloadOpen(true)}
                        className="ml-auto flex items-center gap-1.5 px-3 py-1.5 rounded-lg transition-all duration-200"
                        style={{background: theme.subtle, color: theme.from, border: `1px solid ${theme.from}30`}}
                        onMouseEnter={(e) => {
                            e.currentTarget.style.background = theme.from;
                            e.currentTarget.style.color = "#fff";
                        }}
                        onMouseLeave={(e) => {
                            e.currentTarget.style.background = theme.subtle;
                            e.currentTarget.style.color = theme.from;
                        }}
                    >
                        <Download size={14}/>
                        <span className="text-xs" style={{fontFamily: "var(--font-display)"}}>下载</span>
                    </button>
                )}
            </div>

            {loading && !detail && (
                <div className="flex items-center justify-center py-20">
                    <Loader2 size={32} className="animate-spin" style={{color: theme.from}}/>
                    <span className="ml-3 text-sm" style={{color: "var(--text-secondary)"}}>加载中...</span>
                </div>
            )}

            {error && !loading && (
                <div className="flex items-center gap-2 px-4 py-3 rounded-xl mb-4"
                     style={{background: "rgba(220,38,38,0.08)", border: "1px solid rgba(220,38,38,0.15)"}}>
                    <AlertCircle size={16} style={{color: "#fb7185"}}/>
                    <span className="text-sm" style={{color: "#fb7185"}}>{error}</span>
                </div>
            )}

            {detail && (
                <div className="flex flex-col xl:flex-row gap-4">
                    {/* 左栏：播放器 + 剧集列表 + 信息面板 */}
                    <div className="flex-1 min-w-0 space-y-4">
                        <ArtVideoPlayer
                            ref={playerHandleRef}
                            url={playUrl}
                            isLocalFile={isLocalFile}
                            showCountdown={autoPlayNext.showCountdown}
                            countdownSeconds={autoPlayNext.countdownSeconds}
                            onCancelCountdown={autoPlayNext.cancelAutoPlay}
                        />

                        {/* 剧集列表 — 播放器下方平铺展示 */}
                        {currentSource && (
                            <PlayEpisodeList
                                episodes={currentSource.episodes}
                                activeIndex={activeEpIndex}
                                onSelect={handleEpisodeSelect}
                                vodId={detail?.vod_id}
                                sourceIndex={activeSourceIndex}
                                urlCheckStatuses={m3u8Check.statusMap}
                                urlCheckErrors={m3u8Check.errorMap}
                            />
                        )}

                        {currentSource && currentSource.episodes.length > 1 && (
                            <EpisodeNav activeEpIndex={activeEpIndex} maxEpIndex={maxEpIdx} onPrev={handlePrev}
                                        onNext={handleNext}/>
                        )}

                        <PlayInfoPanel detail={detail} groupKey={groupKey} site={activeDomain}/>

                        {/* 移动端/平板：资源切换放在信息面板下方 */}
                        <div className="xl:hidden">
                            <ResourceSwitcher items={groupItems} activeDomain={activeDomain}
                                              onChange={handleResourceChange}/>
                        </div>
                    </div>

                    {/* 右栏：播放历史 + 资源切换（仅 xl 显示） */}
                    <div className="hidden xl:flex xl:w-70 shrink-0 flex-col gap-4">
                        <PlayHistoryPanel/>
                        <ResourceSwitcher items={groupItems} activeDomain={activeDomain}
                                          onChange={handleResourceChange}/>
                    </div>
                </div>
            )}

            {!loading && !detail && !error && groupItems.length === 0 && !vodIdParam && (
                <div className="flex flex-col items-center justify-center py-20">
                    <AlertCircle size={48} style={{color: "var(--text-tertiary)"}}/>
                    <p className="mt-4 text-sm"
                       style={{color: "var(--text-secondary)"}}>未找到分组数据，请从搜索页进入</p>
                </div>
            )}

            {/* 下载弹窗 */}
            {detail && sources.length > 0 && (
                <DownloadEpisodeDialog
                    open={downloadOpen}
                    onOpenChange={setDownloadOpen}
                    sources={sources}
                    defaultSourceIndex={activeSourceIndex}
                    vodId={detail.vod_id}
                    vodName={detail.vod_name}
                    vodPic={detail.vod_pic ?? ""}
                    resourceDomain={detail.resource_domain}
                    resourceName={detail.resource_name}
                    groupKey={groupKey}
                />
            )}
        </div>
    );
}
