import { useParentContext } from '../contexts/ParentContext';

export function useParent() {
  return useParentContext();
}
