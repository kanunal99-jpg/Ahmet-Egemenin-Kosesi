import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  permittedCategoryIds,
  isVisibleForChild,
} from '../src/utils/childCategoryPolicy.ts';

test('guest and parent accounts retain public catalog access', () => {
  for (const role of [null, 'parent', 'admin', 'guest']) {
    assert.equal(permittedCategoryIds(role, 'user-1', null), null);
  }
});

test('child UI stays closed while policy is pending, unavailable or belongs to another user', () => {
  assert.deepEqual(permittedCategoryIds('child', 'child-1', null), []);
  assert.deepEqual(permittedCategoryIds('child', 'child-1', {
    userId: 'child-1', status: 'error', allowedCategoryIds: null,
  }), []);
  assert.deepEqual(permittedCategoryIds('child', 'child-2', {
    userId: 'child-1', status: 'ready', allowedCategoryIds: null,
  }), []);
  assert.deepEqual(permittedCategoryIds('child', undefined, {
    userId: 'child-1', status: 'ready', allowedCategoryIds: null,
  }), []);
});

test('a verified null means unrestricted, verified [] means no categories', () => {
  assert.equal(permittedCategoryIds('child', 'child-1', {
    userId: 'child-1', status: 'ready', allowedCategoryIds: null,
  }), null);
  assert.deepEqual(permittedCategoryIds('child', 'child-1', {
    userId: 'child-1', status: 'ready', allowedCategoryIds: [],
  }), []);
});

test('restricted child cannot see uncategorized or unapproved videos', () => {
  const ids = permittedCategoryIds('child', 'child-1', {
    userId: 'child-1', status: 'ready', allowedCategoryIds: ['story'],
  });
  assert.equal(isVisibleForChild('story', ids), true);
  assert.equal(isVisibleForChild('game', ids), false);
  assert.equal(isVisibleForChild(null, ids), false);
  assert.equal(isVisibleForChild(undefined, ids), false);
  assert.equal(isVisibleForChild('story', []), false);
  assert.equal(isVisibleForChild(null, null), true);
});
