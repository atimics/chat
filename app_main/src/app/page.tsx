'use client';

import NFTAuthClient from '../../../nft_auth_system/client/NFTAuthClient';
import WalletContextProvider from '../../../nft_auth_system/client/WalletContextProvider';

export default function Home() {
  return (
    <WalletContextProvider>
      <NFTAuthClient />
    </WalletContextProvider>
  );
}
