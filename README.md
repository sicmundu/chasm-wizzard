# Chasm Network: The Testnet Node Adventure 2.0 🧭

Full guide: [link here]

Welcome back, brave explorer, to the **Chasm Network: The Testnet Node Adventure 2.0**! Get ready for an even more epic journey as you set up your Chasm Network Testnet Node. No dragons, but we’ve added some serious firepower with our latest updates. 

## What’s New? 🤔

This repository is still your go-to place for setting up a Chasm Network Testnet Node, but now with more style, more control, and, of course, more fun. We’ve supercharged the script to give you more options, more visibility, and a slicker experience.

## Why This Update Rocks 🎸

- **Launch Multiple Scouts**: Need to run a fleet of scouts? No problem. Spin them up with ease and let them do the work.
- **Log & Status Checks**: Stay in control with easy access to logs and status checks. If a scout is down, you’ll know—and you can fix it with a single command.
- **Sleek New Menu**: We’ve revamped the menu for smoother navigation and a more intuitive experience. It’s like upgrading from a rowboat to a spaceship.

## Your Adventure Begins 🏁

### 1. Clone the Repo

Start by grabbing this repository:

```bash
git clone https://github.com/sicmundu/chasm-wizzard.git
cd chasm-wizzard
```

### 2. Launch the Magic

Next, fire up the script to begin your adventure:

```bash
chmod +x chasm.sh
./chasm.sh
```

### 3. Choose Your Path

When the menu appears, you’ve got options! Whether you’re setting up a new scout, restarting all scouts, or just checking statuses, it’s all at your fingertips.

### 4. Enjoy the Ride 🚀

Once the script finishes, your Chasm Network Testnet Node (or nodes) will be live and kicking. Time to sit back, relax, and admire your handiwork—or, you know, grab a celebratory coffee.

## Under the Hood 🛠️

Here’s a quick breakdown of the wizardry happening behind the scenes:

1. **Dependency Installation**: Ensuring you have all the right tools.
2. **Docker Setup**: The backbone of your node operations.
3. **Scout Management**: Create, restart, or check your scouts with ease.
4. **Firewall Fortification**: Keeping unwanted guests out.
5. **Node Launch**: Liftoff achieved! 🌕

## How to Check Logs & Statuses 🕵️‍♂️

Want to see what your scouts are up to? Here’s how:

1. **Check Scout Names**: Run the script and choose the option to list all running scouts. You’ll get a neat list of scout names.
2. **View Logs**: Use the following command to tail the logs of any scout:
   ```bash
   docker logs -f scout_your_scout_name
   ```
   Replace `your_scout_name` with the name of the scout you want to check.

3. **Check Status**: If you see a scout not performing as expected, restart it directly from the menu, or choose to restart all scouts at once. Easy peasy.

## Got Feedback or Ideas? 💡

We love hearing from you! If you’ve got a killer idea to make this script even better (or just want to add more jokes), fork the repo, make your changes, and send us a pull request. Let’s build something awesome together!

## License 📜

This project is licensed under the MIT License. Check out the `LICENSE` file for all the legal jazz.

---

Happy Node-ing, Adventurer! 🧭