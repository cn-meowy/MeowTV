import { API } from '@/constants/api';
import { post } from './client';
import type { DoubanSubjectsReq, DoubanSubjectsResp, DoubanTagsReq, DoubanTagsResp } from '@/types/api';

/** 获取豆瓣分类列表 */
export function getSubjects(req: DoubanSubjectsReq): Promise<DoubanSubjectsResp> {
  return post<DoubanSubjectsResp>(API.DOUBAN_SUBJECTS, req as unknown as Record<string, unknown>);
}

/** 获取豆瓣标签列表 */
export function getTags(req: DoubanTagsReq): Promise<DoubanTagsResp> {
  return post<DoubanTagsResp>(API.DOUBAN_TAGS, req as unknown as Record<string, unknown>);
}

