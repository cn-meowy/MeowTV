import type { DoubanSubject } from '@/types/api';
import { API } from '@/constants/api';

/** 从 card_subtitle 解析影视信息 */
export function parseCardSubtitle(subtitle?: string) {
  if (!subtitle) return { type: '', genres: [] as string[], year: 0 };

  const parts = subtitle.split(' / ');
  const type = parts[0] || '';
  const genres = parts.length >= 2 ? parts.slice(1, -1).flatMap(p => p.split(' ')) : [];
  const lastPart = parts[parts.length - 1] || '';
  const year = /^\d{4}$/.test(lastPart) ? parseInt(lastPart) : 0;

  return { type, genres, year };
}

/** 将豆瓣封面 URL 中的尺寸标识替换为原图 */
export function replaceToOriginal(coverUrl: string): string {
  if (!coverUrl) return '';
  const sizePatterns = ['s_ratio_poster', 'm_ratio_poster', 'l_ratio_poster'];
  for (const pattern of sizePatterns) {
    const old = `/view/photo/${pattern}/`;
    if (coverUrl.includes(old)) {
      return coverUrl.replace(old, '/view/photo/raw/');
    }
  }
  return coverUrl;
}

/** 将豆瓣原始封面 URL 转为代理 URL */
export function buildProxyCoverUrl(originalUrl: string, token: string): string {
  if (!originalUrl) return '';
  return `${API.DOUBAN_IMAGE_PROXY}?url=${encodeURIComponent(originalUrl)}&token=${token}`;
}

/** MovieCard 可用的数据格式 */
export interface MovieCardData {
  title: string;
  year: number | string;
  rating: number;
  genre: string;
  duration: string;
  image: string;
  badge?: string;
  doubanId?: string;
}

/** HeroSection 可用的数据格式 */
export interface HeroItemData {
  title: string;
  tagline: string;
  description: string;
  year: number;
  rating: number;
  genre: string;
  duration: string;
  image: string;
  doubanId?: string;
}

/** 将 DoubanSubject 转为 MovieCard 可用格式 */
export function subjectToMovieCard(
  subject: DoubanSubject,
  imageToken: string,
): MovieCardData {
  const { genres, year } = parseCardSubtitle(subject.card_subtitle);
  return {
    title: subject.title,
    year,
    rating: parseFloat(subject.rate) || 0,
    genre: genres.join(' ') || '未知',
    duration: subject.type === 'tv' ? '剧集' : '未知',
    image: buildProxyCoverUrl(subject.cover, imageToken),
    doubanId: subject.id,
  };
}

/** 将 DoubanSubject 转为 HeroSection 可用格式 */
export function subjectToHeroItem(
  subject: DoubanSubject,
  imageToken: string,
): HeroItemData {
  const { genres, year, type } = parseCardSubtitle(subject.card_subtitle);
  return {
    title: subject.title,
    tagline: type || '',
    description: '',
    year,
    rating: parseFloat(subject.rate) || 0,
    genre: genres.join(' ') || '未知',
    duration: subject.type === 'tv' ? '剧集' : '未知',
    image: buildProxyCoverUrl(replaceToOriginal(subject.cover), imageToken),
    doubanId: subject.id,
  };
}
