import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import { Button } from "@/components/ui/button";

// Colloquial English version
export default function ComingSoon() {
  return (
    <div className="flex flex-col items-center justify-center h-screen bg-red-600 text-white text-center">
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 1 }}
        className="text-5xl font-bold"
      >
        🧧 Hong Bao is cooking..
      </motion.div>
      <motion.p
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1, duration: 1 }}
        className="mt-4 text-lg"
      >
        The Web3 Red Packet era is coming, are you ready to receive blessings?
      </motion.p>
      <motion.a
        href="https://x.com/hongbao_red"
        target="_blank"
        rel="noopener noreferrer"
        className="mt-6"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 2, duration: 1 }}
      >
        <Button className="flex items-center gap-2 bg-white text-red-600 px-6 py-2 rounded-xl hover:bg-gray-200">
          Follow us on X
        </Button>
      </motion.a>
    </div>
  );
}
