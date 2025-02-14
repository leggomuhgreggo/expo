import { css } from '@emotion/react';
import { borderRadius, theme, spacing } from '@expo/styleguide';
import React, { PropsWithChildren } from 'react';

type SnippetContentProps = PropsWithChildren<{
  alwaysDark?: boolean;
  hideOverflow?: boolean;
  skipPadding?: boolean;
}>;

export const SnippetContent = ({
  children,
  alwaysDark = false,
  hideOverflow = false,
  skipPadding = false,
}: SnippetContentProps) => (
  <div
    css={[
      contentStyle,
      alwaysDark && contentDarkStyle,
      hideOverflow && contentHideOverflow,
      skipPadding && skipPaddingStyle,
    ]}>
    {children}
  </div>
);

const contentStyle = css`
  color: ${theme.text.default};
  background-color: ${theme.background.secondary};
  border: 1px solid ${theme.border.default};
  border-bottom-left-radius: ${borderRadius.medium}px;
  border-bottom-right-radius: ${borderRadius.medium}px;
  padding: ${spacing[4]}px;
  overflow-x: auto;

  code {
    padding-left: 0;
    padding-right: 0;
  }
`;

const contentDarkStyle = css`
  background-color: ${theme.palette.black};
  border-color: transparent;
  white-space: nowrap;
`;

const contentHideOverflow = css`
  overflow: hidden;

  code {
    white-space: nowrap;
  }
`;

const skipPaddingStyle = css({
  padding: 0,
});
