import conventionalCommits from 'conventional-changelog-conventionalcommits';

// The first implementation predates our Conventional Commit policy. Match only
// that immutable commit; once v1.0.0 tags it, it leaves the analyzed range.
const initialImplementation = '945e04ba556427ae90b797d5443035718f21469d';
const { writer } = conventionalCommits();

export default {
  branches: ['main'],
  tagFormat: 'v${version}',
  plugins: [
    ['@semantic-release/commit-analyzer', {
      preset: 'conventionalcommits',
      releaseRules: [{ hash: initialImplementation, release: 'minor' }],
    }],
    ['@semantic-release/release-notes-generator', {
      preset: 'conventionalcommits',
      writerOpts: {
        transform(commit, context) {
          const normalized = commit.hash === initialImplementation
            ? { ...commit, type: 'feat', subject: 'add Markdown task actions, fence copy, and terminal runner' }
            : commit;
          return writer.transform(normalized, context);
        },
      },
    }],
    ['@semantic-release/github', {
      successCommentCondition: false,
      failCommentCondition: false,
      labels: false,
      releasedLabels: false,
      addReleases: false,
    }],
  ],
};
